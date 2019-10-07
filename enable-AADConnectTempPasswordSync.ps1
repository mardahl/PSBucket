#Requires -RunAsAdministrator

# Script to enable "change password on first logon" sync to Azure AD
# @michael_mardahl on twitter

$AADConnector = Get-ADSyncConnector | Where-Object ListName -eq "Windows Azure Active Directory (Microsoft)"
if ($AADConnector.count -eq 1) {

    Write-Host "Enabling ForcePasswordResetOnLogonFeature on connector $($AADConnector.Name)." -ForegroundColor Green
    Set-ADSyncAADCompanyFeature -ConnectorName $AADConnector.Name -ForcePasswordResetOnLogonFeature $true

} else {

    Write-Host "None OR more than one suitable connector found, run this command manually to determine which connector to use:" -ForegroundColor Yellow
    Write-Host '(Get-ADSyncConnector | Where-Object ListName -eq "Windows Azure Active Directory (Microsoft)").Name'
    Write-Host 'Then fill in the connector name you wish to use in this comand:' -ForegroundColor Yellow
    Write-Host 'Set-ADSyncAADCompanyFeature -ConnectorName  "<CONNECTOR NAME FROM PREVIOUS COMMAND>" -ForcePasswordResetOnLogonFeature $true'

}
