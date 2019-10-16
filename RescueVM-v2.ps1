
#Searching For Az module.

$ErrorActionPreference = "Stop"
try{
$module = Get-InstalledModule -Name Az
}
Catch
{ Write-host "No match was found for the specified module , Please install the Az Module" -ForegroundColor Red
}

Write-Output "Using $($module.name) PowerShell Module"
    Import-Module $module.Name



#Logging to Azure and setting the context.

Write-Host "Logging into Azure and Setting the correct Context" -Foregroundcolor Green

Login-AzAccount
$subscriptions = Get-AzSubscription | Select-Object Name 
                $subscription = $subscriptions | Out-GridView -Title "Select the subscription" -OutputMode Single
                Set-AzContext -Subscription $subscription.Name | Out-Null

$Context =Get-AzContext
Write-Host "Current Subscription Context set to":$($Context.Name) -ForegroundColor Yellow


# Getting the details of the affected VM
$ResourceGroup = Read-Host "Enter the Affected Resource Group Name"
$ResourceGroup
$AffectedVM = Get-AzVM -ResourceGroupName $resourcegroup
Write-Host "The name of the Affected VM is : $($AffectedVM.Name)" -ForegroundColor Magenta
$location = $AffectedVM.Location



Write-host "Checking the current state of the affected VM and turning it OFF" -ForegroundColor Green

$CurrentState = Get-AzVM -Name $AffectedVM.Name -Status | Select PowerState

If ( $CurrentState.PowerState -eq 'VM running' )
{
    Write-Host "The VM:$($AffectedVM.Name) is in running state" -ForegroundColor DarkYellow
    Write-Output "Shutting down the VM:$($AffectedVM.Name) ";

    Stop-AzVM -ResourceGroupName $ResourceGroup -Name $AffectedVM.Name -Force
    Write-Output "About to sleep for 10 seconds to check status"
    Start-Sleep -s 10
    $CurrentState = Get-AzVM -Name $AffectedVM.Name -Status | Select PowerState
    $CurrentState
    }


  elseif ( $CurrentState.PowerState -eq 'VM Deallocated' ){


# Creating a Snapshot of the affected VM disk 

Write-Host "Creating a snapshot of the affected VM OS Disk" -BackgroundColor Yellow -ForegroundColor Black

$snapshotName = 'Rescuesnapshot' 

$SnapSourceURI = $AffectedVM.StorageProfile.OsDisk.ManagedDisk.Id 


        <# Creating a Snapshot Config #>

            $snapshot =  New-AzSnapshotConfig `
            -SourceUri $SnapSourceURI `
            -Location $location `
            -CreateOption copy


                        New-AzSnapshot  `
                        -Snapshot $snapshot `
                        -SnapshotName $snapshotName `
                        -ResourceGroupName $resourceGroup 

}

$snapshot = Get-AzSnapshot -ResourceGroupName $resourceGroup -SnapshotName $snapshotName


<# Creating a Managed Disk from the Snapshot #>

    $disk=Get-AzDisk -ResourceGroupName $resourcegroup | Where-Object {$_.Ostype -eq "Windows"}    <# getting the correct OS Disk #>

    $storageType= Get-AzDisk -ResourceGroupName $resourcegroup -DiskName $disk.name   <# getting the SKU #>

    $StorageManagedtype=$storageType.Sku.Name     <# dumping the SKU #>

    $diskConfig = New-AzDiskConfig -SkuName $StorageManagedtype -Location $location -CreateOption Copy -SourceResourceId $snapshot.Id
    $diskName= 'CreatedFromSanp'

Write-Host " Creating the managed disk from Snapshot now" -ForegroundColor Green

New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName $diskName <# Creating the disk now #>

Write-Host "Creating the Rescue VM with the managed disk from Snapshot" -ForegroundColor Yellow

$RescueVMName= 'RescueVM'




<# Creating an Azure VM:Rescue #( Need to work on this to assign a public IP rather Private #>

Write-Output "Creating the new Azure VM"

#VM
$VMsize=$AffectedVM.HardwareProfile | Select-Object -ExpandProperty VMSize
$ComputerName = 'RescueVM'
$VMLocalAdminUser = 'RescueUser'
$VMLocalAdminSecurePassword = ConvertTo-SecureString RescueVM.123456 -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword);

#Network
$NetworkName = "RescueNet"
$NICName = "RescueNIC"
$SubnetName = "RescueSubnet"
$PublicIPAddressName = "RescuePIP"
$SubnetAddressPrefix = "10.0.0.0/24"
$VnetAddressPrefix = "10.0.0.0/16"

$SingleSubnet = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix
$Vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix $VnetAddressPrefix -Subnet $SingleSubnet
$PIP = New-AzPublicIpAddress -Name $PublicIPAddressName -ResourceGroupName $ResourceGroup -Location $Location -AllocationMethod Dynamic
$NIC = New-AzNetworkInterface -Name $NICName -ResourceGroup $ResourceGroup -Location $Location -SubnetId $Vnet.Subnets[0].Id -PublicIpAddressId $PIP.Id

$VirtualMachine = New-AzVMConfig -VMName $ComputerName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter' -Version latest

New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $VirtualMachine -Verbose 

$VirtualMachine.Location = $location

<# Attaching the affected VM OS disk to the Rescue VM #>

$RescueVMName= Get-AzVM -Name $virtualmachine.Name -ResourceGroupName $resourcegroup
$diskToAdd = Get-AzDisk -ResourceGroupName $rgName -DiskName $diskname
Add-AzVMDataDisk -CreateOption Attach -Lun 1 -VM $RescueVMName -ManagedDiskId $diskToAdd.Id
Update-AzVM -VM $Rescuevmname -ResourceGroupName $resourcegroup

<# dumping RDP Info to user for connect and do troubleshooting#>

$RDPIP=Get-AzPublicIpAddress -ResourceGroupName $ResourceGroup | Select "IpAddress"
Write-Output " The IP address to connect to RDP is :$($RDPIP.IpAddress)";
Write-Output " The UserName to connect to RDP is :RescueUser";
Write-Output " The Password to connect to RDP is :RescueVM.123456";



<# Swapping the OS Disk #>

Write-Warning "This will swap the OS disk to the affected VM , Please type yes only if all the troubleshooting is done"
$SwapOSAck=Read-Host -Prompt " Type Yes to Swap the OS disk" 

If ( $SwapOSAck -eq 'Yes' )
{
Stop-AzVm -ResourceGroupName $resourcegroup -Name $affectedVM.Name -Force
Stop-AzVm -ResourceGroupName $resourcegroup -Name $virtualmachine.Name -Force
$VirtualMachineDiskDetach = Get-AzVM -ResourceGroupName $ResourceGroup -Name RescueVM
Remove-AzVMDataDisk -VM $VirtualMachineDiskDetach -Name CreatedFROMSanp
Update-AzVM -ResourceGroupName $ResourceGroup -VM $VirtualMachineDiskDetach
$RepairedDisk = Get-AzDisk -ResourceGroupName $ResourceGroup -Name $diskName
Set-AzVMOSDisk -VM $AffectedVM -ManagedDiskId $RepairedDisk.Id -Name $RepairedDisk.Name
Update-AzVM -ResourceGroupName $ResourceGroup -VM $AffectedVM
Start-AzVM -Name $AffectedVM.Name -ResourceGroupName $ResourceGroup

}
            elseif ( $SwapOSAck -ne 'Yes' ){
            Write-Output "Invalid Input provided , Exitting script";


    }



<# Cleaning up the resources created for repair #>

$CleanupAck =Read-Host -Prompt " Type Yes to start cleaning up resources" 


If ( $CleanupAck -eq 'Yes' )
{
    Write-Output "The user has pressed to clean-up the resources created for repair";
    Write-Output "Starting Cleaning up Resources"

    #Checking the state of the RescueVM and turning it OFF

   $RescueVMPostRepairState = Get-AzVM -Name $virtualmachine.Name -Status | Select PowerState

         If ( $RescueVMPostRepairState.PowerState -eq 'VM running' )
                {
   
    Write-Output "Shutting down the VM:$($virtualmachine.Name) ";

    Stop-AzVM -ResourceGroupName $ResourceGroup -Name $virtualmachine.Name -Force
    Write-Output "About to sleep for 20 seconds to check status"
    Start-Sleep -s 20
    $RescueVMPostRepairState = Get-AzVM -Name $virtualmachine.Name -Status | Select PowerState
    $RescueVMPostRepairState
    Remove-AzVM -ResourceGroupName $ResourceGroup -Name $virtualmachine.Name -Force
    Remove-AzNetworkInterface -Name $NICName -ResourceGroup Test1 -Force
    Remove-AzPublicIpAddress -Name $PublicIPAddressName -ResourceGroupName Test1 -Force
    Remove-AzSnapshot -ResourceGroupName $ResourceGroup -SnapshotName $snapshot.Name -Force
    Remove-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroup -Force
  
    $rescueOSdisk=Get-AzDisk -ResourceGroupName $ResourceGroup -DiskName '*Rescue*'
    Remove-AzDisk -ResourceGroupName $ResourceGroup -DiskName $rescueOSdisk.name -Force


    }


            elseif ( $RescueVMPostRepairState.PowerState -eq 'VM Deallocated' ){
            Write-Output "VM is in shutdown state";
            Stop-AzVM -ResourceGroupName $ResourceGroup -Name $virtualmachine.Name -Force
    Write-Output "About to sleep for 20 seconds to check status"
    Start-Sleep -s 20
    $RescueVMPostRepairState = Get-AzVM -Name $virtualmachine.Name -Status | Select PowerState
    $RescueVMPostRepairState
    Remove-AzVM -ResourceGroupName $ResourceGroup -Name $virtualmachine.Name -Force
    Remove-AzNetworkInterface -Name $NICName -ResourceGroup Test1 -Force
    Remove-AzPublicIpAddress -Name $PublicIPAddressName -ResourceGroupName Test1 -Force
    Remove-AzSnapshot -ResourceGroupName $ResourceGroup -SnapshotName $snapshot.Name -Force
    Remove-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroup -Force
  
    $rescueOSdisk=Get-AzDisk -ResourceGroupName $ResourceGroup -DiskName '*Rescue*'
    Remove-AzDisk -ResourceGroupName $ResourceGroup -DiskName $rescueOSdisk.name -Force


    }

 elseif ( $CleanupAck -ne 'Yes' )
 {
    Write-Output "Invalid input provided. Exitting script - Please cleanup the resources manually from the Resource Group";
    }
    }










   