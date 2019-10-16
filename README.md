# AzureScript
The First script is to help users when Azure VM's go into No-Boot state.
This will input a resource group ( affected ) - Create a Rescue VM in the same RG - Attach the affected disk to the rescue VM - allow you to press a key
You can troubleshoot as On-prem issue. After troubleshooting , press the key - and it will swap the OS disk and cleanup the unnecessary resources.



Second script is run an automation runbook through powershell
