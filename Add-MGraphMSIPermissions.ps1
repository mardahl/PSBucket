<#
.SYNOPSIS
Granting single/multiple permissions to a Managed Identity using the Microsoft Graph Powershell SDK

.DESCRIPTION
This script will grant the specified permissions to the specified managed identity (MSI). 
It will not remove any existing permissions, unless you set $clearExistingPermissions to $true.

.PARAMETER APIAppName
The display name of the resource (API) you want to grant permissions to (e.g. Microsoft Graph)

.PARAMETER DisplayNameOfMSI
The display name of your managed identity

.PARAMETER Permissions
The permissions to be granted (in powershell array format)
Example: @("group.readwrite.all","user.read.all") #You can enter a single value here if you like.

.PARAMETER ClearExistingPermissions
If set to $true, existing permissions will be removed before applying the new permissions.

.EXAMPLE
Add-MGraphMSIPermissions.ps1 -APIAppName "Microsoft Graph" -DisplayNameOfMSI "myFunctionApp" -Permissions @("group.readwrite.all","user.read.all") -ClearExistingPermissions $true

.NOTES
Script by Michael Mardahl (github.com/mardahl)
Granting multiple permissions to a Managed Identity using the Microsoft Graph Powershell SDK
Modified version of the Microsoft Github example
use "install-module microsoft.graph" in you don't have the Microsoft Graph API Powershell SDK module installed

#>
#Requires -Modules Microsoft.Graph

#region declarations

#parameter declarations that default to hardcoded values if not provided as parameters
#Remember that you must enter the correct API name for the permission you are trying to assign. e.g. "Office 365 Exchange Online" if you want to do exchange online stuff.
param(
    [Parameter(Mandatory=$false)]
    [string]$APIAppName = "Microsoft Graph",
    [Parameter(Mandatory=$false)]
    [string]$DisplayNameOfMSI = "MyAwesomeManagedIdentity",
    [Parameter(Mandatory=$false)]
    [array]$Permissions = @("group.readwrite.all","user.read.all"),
    [Parameter(Mandatory=$false)]
    [bool]$ClearExistingPermissions = $false
)

#endregion declarations

#region execute

# Define dynamic variables
$ServicePrincipalFilter = "displayName eq '$($DisplayNameOfMSI)'" 
$ApiServicePrincipalFilter = "displayName eq '$($APIAppName)'"

# Connect to MG Graph - scopes must be consented the first time you run this. 
# Connect with Global Administrator account first time will make things easy for you.
Connect-MgGraph -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All" -UseDeviceAuthentication

# Get the service principal for your managed identity.
$ServicePrincipal = Get-MgServicePrincipal -Filter $ServicePrincipalFilter

# Get the service principal for Microsoft Graph. 
# Result should be AppId 00000003-0000-0000-c000-000000000000
$ApiServicePrincipal = Get-MgServicePrincipal -Filter "$ApiServicePrincipalFilter"
if ($ApiServicePrincipal) {
    write-host "Found API appId $($ApiServicePrincipal.Id)"
} else {
    Write-Error "No API exists for $APIAppName!"
}

#Remove existing permissions if $clearExistingPermissions is $true
if($clearExistingPermissions) {
    Write-Host "Removing existing permissions because `$clearExistingPermissions is set to `$true"
    # Get all application permissions for the managed identity service principal
    $MSIApplicationPermissions = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id | Where-Object { $_.PrincipalType -eq "ServicePrincipal" }

    # Remove all application permissions for the managed identity service principal
    $MSIApplicationPermissions | ForEach-Object {
        Write-Host "Removing App Role Assignment '$($_.Id)'"
        Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id -AppRoleAssignmentId $_.Id
    }
}

# Apply permissions
Foreach ($Scope in $Permissions) {
    Write-Host "Getting App Role '$Scope'"
    $AppRole = $ApiServicePrincipal.AppRoles | Where-Object {$_.Value -eq $Scope -and $_.AllowedMemberTypes -contains "Application"}
    if ($null -eq $AppRole) {
        Write-Error "Could not find the specified App Role on the Api Service Principal ($APIAppName)"
        continue
    }
    if ($AppRole -is [array]) {
        Write-Error "Multiple App Roles found that match the request"
        Write-Host $AppRole.Value
        continue
    }
    Write-Host "Found App Role, Id '$($AppRole.Id)'"

    $ExistingRoleAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id | Where-Object { $_.AppRoleId -eq $AppRole.Id }
    if ($null -eq $existingRoleAssignment) {
        Write-Host "Assigning App Role '$($AppRole.Value)' - $($AppRole.Description)"
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id -PrincipalId $ServicePrincipal.Id -ResourceId $ApiServicePrincipal.Id -AppRoleId $AppRole.Id
    } else {
        Write-Host "App Role has already been assigned, skipping"
    }
}
Write-Host "Completed assigning permissions scopes for $DisplayNameOfMSI"
#endregion execute
