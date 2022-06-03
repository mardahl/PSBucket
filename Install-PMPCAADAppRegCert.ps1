 <#
    BETA - Script to create self-signed 10 year valid cert and upload to App registration to use with PMPC
    Quick and dirty by Michael Mardahl (github.com/mardahl)
    MIT License - use at own risk

    Just run this on the publisher PC - notice the required modules that need to be installed.
    Delete the exported PFX if you don't have a use for it (dont leave it lying around)
#>
#Requires -Module Az.Accounts,Az.Resources
#Requires -RunAsAdministrator

$PfxCertPath = "C:\PMPCIntuneAppCert-$(get-date -Format ddMMMyyyyhhss).pfx" #Place to store temporary cert file
$CertificatePassword = "$(get-date -Format ddMMMyyyyhhss)veryVERYsecret" #A password you choose to save the cert with
$certificateName = "PMPCIntuneAppCert-$(get-date -Format ddMMMyyyyhhss)" #A certificate name you choose
$ErrorActionPreference = 'Stop'

try {
    Get-AzSubscription -ErrorAction stop | out-null
} catch {
    Connect-AzAccount -DeviceCode
    if (-not (Get-AzSubscription)) {
        exit 1
    }
}

#select AppRegistration interactively
$AppRegObj = Get-AzADApplication | Out-GridView -PassThru -Title "Select PMPC AppRegistration"
$AppClientID = [string]$AppRegObj.AppId

 
try {

#Creating secure password string
$SecurePassword = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force
 
#Creating 10 year valid self-signed cert
$NewCert = New-SelfSignedCertificate -CertStoreLocation Cert:\LocalMachine\My `
                                     -DnsName $certificateName `
                                     -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' `
                                     -KeyAlgorithm RSA `
                                     -KeyLength 2048 `
                                     -NotAfter (Get-Date).AddYears(10)
#Exporting cert to file
Export-PfxCertificate -FilePath $PfxCertPath `
                      -Password $SecurePassword `
                      -Cert $NewCert -Force
} catch {
    $_
    exit 1
}



#Configure required flags on the certificate
$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable `
    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet `
    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet

# Load the certificate into memory
$PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($PfxCertPath, $CertificatePassword, $flags) -ErrorAction Stop



#Upload cert to Azure App Registration
$binCert = $PfxCert.GetRawCertData() 
$certValue = [System.Convert]::ToBase64String($binCert)
New-AzADAppCredential -ApplicationId $AppClientID -CertValue $certValue -StartDate $PfxCert.NotBefore -EndDate $PfxCert.NotAfter 
