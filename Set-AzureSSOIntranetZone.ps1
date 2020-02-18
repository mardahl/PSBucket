<#
.SYNOPSIS
    Configure intranet zone to allow Azure SSO
.DESCRIPTION
    This script can be used to configure Azure SSO with Intune, instead of GPP as done here: https://docs.microsoft.com/en-us/azure/active-directory/hybrid/how-to-connect-sso-quick-start#group-policy-preference-option---detailed-steps
.EXAMPLE
    Deploy as a PowerShell script through Intune, remember to execute in 64bit and as the user, then assign to the user.
.NOTES
    NAME: Set-AzureSSOIntranetZone.ps1
    VERSION: 1a
    .COPYRIGHT
    @michael_mardahl / https://www.iphase.dk
    Licensed under the MIT license.
    Please credit me if you fint this script useful and do some cool things with it.
#>
Write-Verbose "Adding SSO URL to Intranet Zone via Registry..." -Verbose
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\microsoftazuread-sso.com\"
$regKey = "autologon"
New-Item -Path $regPath -Name $regKey –Force
New-ItemProperty -Path $($regPath + $regKey) -Name "https" -Value "1" -PropertyType DWord -Force -Confirm:$false
Write-Verbose "Done!" -Verbose