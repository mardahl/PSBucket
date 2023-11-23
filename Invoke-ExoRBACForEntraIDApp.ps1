<#
.SYNOPSIS
    A script to enable RBAC permissions to an Entra ID App in Exchange Online. Scoping access to a native Administrative Unit.

.DESCRIPTION
    This script will create an intermediary Service Principal in Exchange Online and add the required roles to it. 
    The intermediary Service Principal will be scoped to a native Administrative Unit in Exchange Online.

.EXAMPLE
    Adjust the Declarations with values from Entra ID and Exchange Online Application Roles and run the script.

.NOTES
    Version:        1.0
    Author:         Michael Mardahl
    Creation Date:  2023-11-23
    Purpose/Change: Initial script development
    
.LINK
    https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac
    https://github.com/mardahl

#>
#Requires -Module ExchangeOnlineManagement

#declarations
$EntraAppName = "My mail integration app" #From the App Reg, not the Enterprise App
$EntraAppId = "cergerg7-9erte-4er5-9ff3-171ywershg8" #From the App Reg, not the Enterprise App
$EntraAppObectId = "0dtyjhh6-ert5-u6t7-afgg-dsgsg06a" #From the App Reg, not the Enterprise App
$EntraAdministativeUnitObjectId = "ceggss8-eegsegf-4sgd-8gb0-c8gg23eggf3b" #The Entra ID native Administrative unit Object Id
$ExoAppRoles = @("Application Calendars.ReadWrite","Application Mail.ReadWrite") #Native Exchange Online App Roles

#executing the connection to Exchange Online
Connect-ExchangeOnline

#creating intermediary Service Principal in the Exchange Online environment
Write-Host "Creating intermediary Service Principal for $EntraAppName"
$exoSP = New-ServicePrincipal -AppId $EntraAppId -ObjectId $EntraAppObectId -DisplayName "EntraID - $EntraAppName"
#Adding scoping to the intermediary Service Principal for the administrative unit (looping through list of roles defined in variable $ExoAppRoles)
foreach ($role in $ExoAppRoles) {
    #Writting what roles is being added to the intermediary Service Principal
    Write-Host "Adding role $role to $EntraAppName"
    try {
        $result = Get-ManagementRoleAssignment -App $exoSP.AppId -Role $role -RecipientAdministrativeUnitScope $EntraAdministativeUnitObjectId
    }
    catch {
        Write-Host "Role $role not found on $EntraAppName"
        #writing the exception message
        Write-Host $_.Exception.Message
    }
}
Disconnect-ExchangeOnline
exit 0
#test command for manual execution use once you are done.
Test-ServicePrincipalAuthorization -Identity $exoSP.AppId -resource "name@domain.com"
