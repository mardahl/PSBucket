<#
.SYNOPSIS
  Gets Azure AD Group and sets its permissions on a Sharepoint List Item.
.DESCRIPTION
  Connect to Azure AD to get the ID of a specific AAD Security Group, then connects to SharepointOnline to set that groups permissions on a list item.
.NOTES
  Version:        1.0
  Author:         Michael Mardahl
  Creation Date:  Oktober 8th 2020
  Purpose/Change: Initial script development
  License:        MIT, Please leave author credits
  
.EXAMPLE
  Run the script as is after modyfying the declarations
#>
#Requires -Modules SharePointPnPPowerShellOnline, AzureAd

#Declarations
$SPOSite = "https://<tenantname>.sharepoint.com/sites/<MySiteName>" #List url in Sharepoint Online
$SPOList = "MyList" #The list that holds the items your wish to set permissions on
$ItemId = "xxxx" #Id op the list item
$SGName = "MySecurityGroup" #AAD Group Name
$Permissions = "Editor" #Find the right ones for your tenant by running Get-PnPRoleDefinition (it's language dependent!)

try {
    #Connect to Sharepoint Online
    Connect-PnPOnline -Url $SPOSite -UseWebLogin -ErrorAction Stop
    #Connect to Azure AD
    Connect-AzureAD -ErrorAction Stop
} catch {
    Write-Output "Either Azure AD or Sharepoint login failed - Stopping script!"
    exit 1
}

#Find AD Group ID from name and convert to SPO naming
$groupObj = Get-AzureADGroup -SearchString $SGName | Where-Object DisplayName -EQ $SGName
$groupId = 'c:0t.c|tenant|{0}' -f $groupObj.ObjectId
Write-Verbose "Found ID of group: $($groupObj.DisplayName)" -Verbose

#Testing group existence before doing anything rash
if($AADGroupSPO = Get-PnPUser -Identity $groupId){
    Write-Verbose "Setting `"$Permissions`" for group: $($groupObj.DisplayName) on list item Id no. $ItemId " -Verbose
    Set-PnPListItemPermission -Identity $ItemId -List $SPOList -AddRole $Permissions -User $groupId -ErrorAction Continue
}
