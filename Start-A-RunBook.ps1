
#Logging to Azure.
Write-Host "Logging into Azure and Setting the correct Context" -Foregroundcolor Green

Login-AzAccount
$subscriptions = Get-AzSubscription | Select-Object Name 
                $subscription = $subscriptions | Out-GridView -Title "Select the subscription" -OutputMode Single
                Set-AzContext -Subscription $subscription.Name | Out-Null

$Context =Get-AzContext
Write-Host "Current Subscription Context set to":$($Context.Name) -ForegroundColor Yellow

#Selecting an Azure Auto Acct.
$AutomationAccountNames = Get-AzAutomationAccount | Select-Object AutomationAccountName,ResourceGroupName
$AutomationAccountName = $AutomationAccountNames | Out-GridView -Title "Select the Automation Account" -OutputMode Single
$AutomationAccountName.ResourceGroupName
Write-Host "The current Automation Account selected is : $($AutomationAccountName.AutomationAccountName)"


#Selecting a Runbook from the list
$RunBooks=Get-AzAutomationRunbook -AutomationAccountName $AutomationAccountName.AutomationAccountName -ResourceGroupName $AutomationAccountName.ResourceGroupName | Select-Object Name
$Runbook = $RunBooks | Out-GridView -Title "Select a Runbook to run" -OutputMode Single

#Running the selected Runbook
Start-AzAutomationRunbook -AutomationAccountName $AutomationAccountName.AutomationAccountName -Name $Runbook.Name -ResourceGroupName $AutomationAccountName.ResourceGroupName

