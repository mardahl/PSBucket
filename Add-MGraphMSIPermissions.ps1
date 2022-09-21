<#
.NOTES
Quick and dirty script by Michael Mardahl (github.com/mardahl)

A PS script to be executed from Azure Cloud Shell - granting multiple Microsoft Graph permissions to a Managed Identity

FYI: You can replace the Id in $AppId with other App Id's if you need to grant permission like Machine.Isolate for Microsoft Defender for Endpoint App.
#>

$AppId = "00000003-0000-0000-c000-000000000000" #default is the MS Graph AppId
$DisplayNameOfMSI="myAppManagedIdentity"
$Permissions = @("user.read.all","reports.read.all","groupmember.read.all","UserAuthenticationMethod.ReadWrite.All") #You can enter a single value here if you like.

Connect-AzureAD
$ServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$AppId'"
$MSI = (Get-AzureADServicePrincipal -Filter "displayName eq '$DisplayNameOfMSI'")
Start-Sleep -Seconds 7

#Setting permissions one at a 
foreach ($PermissionName in $Permissions) {
    $AppRole = $ServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $ServicePrincipal.ObjectId -Id $AppRole.Id
}
