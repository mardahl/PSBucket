#Requires -RunAsAdministrator

# Script to enable "change password on first logon" sync to Azure AD
# @michael_mardahl on twitter
# According to: https://docs.microsoft.com/en-us/azure/active-directory/hybrid/how-to-connect-password-hash-synchronization#public-preview-of-synchronizing-temporary-passwords-and-force-password-on-next-logon

$AADConnector = Get-ADSyncConnector | Where-Object ListName -eq "Windows Azure Active Directory (Microsoft)"
if ($AADConnector.count -eq 1) {

    Write-Host "Enabling ForcePasswordResetOnLogonFeature" -ForegroundColor Green
    Set-ADSyncAADCompanyFeature -ForcePasswordResetOnLogonFeature $true

} else {

    Write-Host "None OR more than one suitable connector found, run this command manually to determine which connector to use:" -ForegroundColor Yellow
    Write-Host '(Get-ADSyncConnector | Where-Object ListName -eq "Windows Azure Active Directory (Microsoft)").Name'
    Write-Host 'Then fill in the connector name you wish to use in this comand:' -ForegroundColor Yellow
    Write-Host 'Set-ADSyncAADCompanyFeature -ConnectorName  "<CONNECTOR NAME FROM PREVIOUS COMMAND>" -ForcePasswordResetOnLogonFeature $true'

}
