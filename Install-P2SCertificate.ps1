<#
.SYNOPSIS
    Creates a Self-Signed certificate that can be used with Azure P2S VPN for testing purposes
.DESCRIPTION
    (c) Michael Mardahl <github.com/mardahl>.
    Script provided as-is without any warranty of any kind. Use it freely at your own risks.
    MIT License, feel free to distribute and use as you like, leave author information.
.INPUTS
    None
.OUTPUTS
    Base64 encoded root certificate string for use in Azure VPN Gateway configuration.
    AzP2SRootCert in LocalMachine certificate store (/root)
    AzP2SChildCert in CurrentUser certificate store (/my)
.NOTES
    Version:        1.0
    Author:         Michael Mardahl
    Twitter: @michael_mardahl
    Blogging on: www.msendpointmgr.com
    Creation Date:  08 May 2020
    Purpose/Change: Initial script development
.EXAMPLE
    .\Install-P2SCertificate.ps1
    User must have administrative access and execute the script in an elevated PS Session.
#>

#Requires -Version 3
#Requires -RunAsAdministrator

#region Functions

function Invoke-GenerateRootCert() {
    #Function that generates a new root certificate for signing.

    try {
        $rootCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature -Subject "CN=AzP2SRootCert" `
        -KeyExportPolicy Exportable -HashAlgorithm sha256 -KeyLength 2048 -CertStoreLocation `
        "Cert:\LocalMachine\My" -KeyUsageProperty Sign -KeyUsage CertSign -ErrorAction Stop
    } catch {
        Write-Error $_
        exit 1
    }

    return $rootCert
}

function Invoke-GenerateChildCert() {
    #Function that generates a user certificate based on a specific root signing certificate.

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        $RootCert
    )

    try {
        New-SelfSignedCertificate -Type Custom -KeySpec Signature `
        -Subject "CN=AzP2SChildCert" -KeyExportPolicy Exportable `
        -HashAlgorithm sha256 -KeyLength 2048 `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -Signer $RootCert -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2") -ErrorAction Stop | Out-Null
    } catch {
        Write-Error $_
        exit 1
    }
}

#endregion Functions

#region Execute

Write-Verbose "Generating root certificate for Azure P2S." -Verbose
$RootCertObj = Invoke-GenerateRootCert

Write-Verbose "Generating self-signed child certificate." -Verbose
Invoke-GenerateChildCert -RootCert $RootCertObj

Write-Verbose "Outputting Base64 encoded root certificate for you to input into the Azure P2S configuration." -Verbose
[System.Convert]::ToBase64String($rootCertObj.RawData)


#Cleanup
Move-Item -path cert:\LocalMachine\My\$($rootCertObj.Thumbprint) -Destination cert:\LocalMachine\Root\
Clear-Variable $rootCertObj

#endregion Execute
