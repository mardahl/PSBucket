/*
.NOTES
Quick and dirty script by Michael Mardahl (github.com/mardahl)

A PS script to be executed from Azure Cloud Shell - granting multiple Microsoft Graph permissions to a Managed Identity
*/

$MGraphAppId = "00000003-0000-0000-c000-000000000000"
$DisplayNameOfMSI="AA-MFA-Prepopulate"
$Permissions = @("user.read.all","reports.read.all","groupmember.read.all","UserAuthenticationMethod.ReadWrite.All")

Connect-AzureAD
$GraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$MGraphAppId'"
$MSI = (Get-AzureADServicePrincipal -Filter "displayName eq '$DisplayNameOfMSI'")
Start-Sleep -Seconds 10

foreach ($PermissionName in $Permissions) {
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $GraphServicePrincipal.ObjectId -Id $AppRole.Id
}
