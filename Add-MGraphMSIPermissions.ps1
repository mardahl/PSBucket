<#
.NOTES
Quick and dirty script by Michael Mardahl (github.com/mardahl)

A PS script to be executed from Azure Cloud Shell - granting multiple Microsoft Graph permissions to a Managed Identity

This version of the script defaults to clearing out any previous permissions!

#>

#region declarations

#Application Id of the resource you want to grant permissions to (e.g. Microsoft Graph)
$AppId = "00000003-0000-0000-c000-000000000000" #default is the MS Graph AppId

#Display name of your managed identity
$DisplayNameOfMSI="myCoolManagedIdentityName"

#permissions to be granted (in powershell array format)
$Permissions = @("group.readwrite.all","user.read.all") #You can enter a single value here if you like.

#Clear existing permissions?
$clearExistingPermissions = $true

#endregion declarations

#region execute

#connect to Azure AD Powershell
Connect-AzureAD

# Get the Managed Identity Service Principal using displayName
$MSI = (Get-AzureADServicePrincipal -Filter "displayName eq '$DisplayNameOfMSI'")
start-sleep -seconds 3

#Remove existing permissions if $clearExistingPermissions is $true
if($clearExistingPermissions) {
    # Get all application permissions for the managed identity service principal
    $MSIApplicationPermissions = Get-AzureADServiceAppRoleAssignedTo -ObjectId $MSI.ObjectId -All $true | Where-Object { $_.PrincipalType -eq "ServicePrincipal" }

    # Remove all application permissions for the managed identity service principal
    $MSIApplicationPermissions | ForEach-Object {
        Remove-AzureADServiceAppRoleAssignment -ObjectId $_.PrincipalId -AppRoleAssignmentId $_.objectId
    }
}

#Get service principal for the application that we are granting permissions to
$ResourceServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$AppId'"

#Setting permissions one at a time
foreach ($PermissionName in $Permissions) {
    $AppRole = $ResourceServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $ResourceServicePrincipal.ObjectId -Id $AppRole.Id
}

#endregion execute
