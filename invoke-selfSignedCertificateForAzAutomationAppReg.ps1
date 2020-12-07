<#
.SYNOPSIS
    Script to create a 10 year valid self-signed certificate for use as authentication in Azure Automation against an App registration.
.DESCRIPTION
    This script will configure the defined Azure Automation account and App Registration with a 10 year valid certificate.
    The script will also install this certificate in the current users certificate store for local powershell access to the app registration.
.INPUTS
    None
.OUTPUTS
    none
.NOTES
  Version       : 1.0b
  Author        : Michael Mardahl
  Twitter       : @michael_mardahl
  Blogging on   : iphase.dk & www.msendpointmgr.com
  Creation Date : 07 Dec 2020
  Purpose/Change: Initial script development
.EXAMPLE
  execute invoke-selfSignedCertificateForAzAutomationAppReg.ps1 in Powershell ISE to view output.
.NOTES
  Requires the following modules to be installed:
  Az
#>
#Requires -Modules Az

$AutomationAccountName = "myAutomationAccount" #Name of Automation account that needs certificate auth from app registration
$AppClientID = "0wefaweffe-fwerfa-4werfed-93338-f5asdfcc5d4a" # App Id from Azure AD that needs certificate auth
$PfxCertPath = '.\AzureAppAuth.pfx' #Place to store temporary cert file (you can delete this afterwards).
$CertificatePassword = "945FERFr-$(get-date -format ddMMyyyy)" #A password you choose to save the cert with (you can delete the cert file, if you don't explicitly need it).
$certificateName = "AZAppCert$(get-date -format ddMMyyyy)" #A certificate name you choose
$ResourceGroupName = "myAutomationAccountresourceGroup" #resource group containing Azure Automation account.
$ErrorActionPreference = 'Stop'

#Connecting to Azure
try {
  Connect-AzAccount
} catch {
  $_
  exit 1
}
 
try {
  #Creating secure password string
  $SecurePassword = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force

  #Creating 10 year valid self-signed cert
  $NewCert = New-SelfSignedCertificate -CertStoreLocation Cert:\CurrentUser\My `
                                       -DnsName $certificateName `
                                       -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' `
                                       -KeyAlgorithm RSA `
                                       -KeyLength 2048 `
                                       -NotAfter (Get-Date).AddYears(10)
  #Exporting cert to file
  Export-PfxCertificate -FilePath $PfxCertPath `
                      -Password $SecurePassword `
                      -Cert $NewCert
} catch {
    $_
    exit 1
}


#upload to Azure Automation

#Configure required flags on the certificate
$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable `
    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet `
    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet

# Load the certificate into memory
$PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($PfxCertPath, $CertificatePassword, $flags)

# Export the certificate as base 64 string into azure automation
$Base64Value = [System.Convert]::ToBase64String($PfxCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12))
$Thumbprint = $PfxCert.Thumbprint

#Creating JSON payload
$json = @"
{
    '`$schema': 'https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#',
    'contentVersion': '1.0.0.0',
    'resources': [
        {
            'name': '$AutomationAccountName/$certificateName',
            'type': 'Microsoft.Automation/automationAccounts/certificates',
            'apiVersion': '2015-10-31',
            'properties': {
                'base64Value': '$Base64Value',
                'thumbprint': '$Thumbprint',
                'isExportable': true
            }
        }
    ]
}
"@

#Save JSON payload as deployment template file and deploy to Azure Automation
$json | out-file .\CertPayload.json
New-AzResourceGroupDeployment -Name NewCert -ResourceGroupName $ResourceGroupName -TemplateFile .\CertPayload.json
#Cleanup template payload
Remove-Item .\CertPayload.json

#Upload cert to Azure App Registration
$binCert = $PfxCert.GetRawCertData() 
$credValue = [System.Convert]::ToBase64String($binCert)
New-AzADAppCredential -ApplicationId $AppClientID -CertValue $credValue -StartDate $PfxCert.NotBefore -EndDate $PfxCert.NotAfter
Remove-Item $PfxCertPath
