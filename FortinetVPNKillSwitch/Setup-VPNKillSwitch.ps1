#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Windows Firewall as a VPN kill switch for FortiClient.
.DESCRIPTION
    FortiClient's SSL VPN adapter registers under the Domain firewall profile,
    while the physical NIC uses Public (or Private). This script:
    - Blocks outbound on Public and Private profiles (no internet without VPN)
    - Leaves Domain profile outbound as Allow (VPN tunnel traffic flows freely)
    - Allows all FortiClient executables on Public/Private to establish the VPN
    - Allows svchost.exe for NLA (domain detection), DNS, DHCP, and NCSI
    - Adds loopback rules for local connectivity
    Run Undo-VPNKillSwitch.ps1 to revert all changes.
#>

$ErrorActionPreference = "Stop"
$RulePrefix = "VPNKillSwitch"

# --- Configuration -----------------------------------------------------------
# All FortiClient executables that may need network access to establish VPN.
$FortiClientDir = "C:\Program Files\Fortinet\FortiClient"
$FortiClientExes = @(
    "FortiClient.exe"
    "FortiClientConsole.exe"
    "FortiClientSecurity.exe"
    "FortiSSLVPNdaemon.exe"
    "FortiSSLVPNsys.exe"
    "FortiTray.exe"
    "FortiVPN.exe"
    "FortiGui.exe"
    "FortiAuth.exe"
    "FCAuth.exe"
    "FCCOMInt.exe"
    "FCConfig.exe"
    "ipsec.exe"
    "FSSOMA.exe"
)

# VPN gateway IP(s). Add yours here to allow IKE/IPsec if needed.
# $VPNGatewayIPs = @("203.0.113.10")
# ------------------------------------------------------------------------------

Write-Host "=== VPN Kill Switch Setup ===" -ForegroundColor Cyan

# 1. Remove any existing kill switch rules (idempotent re-run)
Write-Host "Cleaning up any previous kill switch rules..."
Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

# 2. Record current default outbound action so undo can restore it
$profiles = Get-NetFirewallProfile
$savedState = $profiles | Select-Object Name, DefaultOutboundAction
$savedState | Export-Clixml -Path "$env:ProgramData\VPNKillSwitch_SavedState.xml" -Force
Write-Host "Saved current firewall profile state to $env:ProgramData\VPNKillSwitch_SavedState.xml"

# 3. Block outbound on Public and Private profiles (physical NIC)
#    Leave Domain profile as Allow (FortiClient VPN adapter uses Domain once connected)
Write-Host "Setting default outbound action..."
Set-NetFirewallProfile -Profile Public, Private -DefaultOutboundAction Block
Set-NetFirewallProfile -Profile Domain -DefaultOutboundAction Allow
Write-Host "  Public/Private: BLOCK (physical NIC - no internet without VPN)" -ForegroundColor Yellow
Write-Host "  Domain:         ALLOW (VPN tunnel traffic flows freely)" -ForegroundColor Green

# 4. Allow FortiClient processes on Public/Private so VPN can be established
Write-Host "Allowing FortiClient executables..."
foreach ($exe in $FortiClientExes) {
    $fullPath = Join-Path $FortiClientDir $exe
    if (Test-Path $fullPath) {
        $name = "$RulePrefix - Allow $exe"
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Program $fullPath -Action Allow -Profile Public, Private | Out-Null
        Write-Host "  Allowed: $exe" -ForegroundColor Green
    } else {
        Write-Host "  Skipped (not found): $exe" -ForegroundColor DarkGray
    }
}

# 5. Allow svchost.exe on Public/Private (handles DNS Client, DHCP, NCSI, and
#    critically NLA - Network Location Awareness). NLA must reach a Domain Controller
#    over the VPN adapter to reclassify it from Public to Domain. Without this,
#    the VPN connects but the profile never switches and traffic stays blocked.
New-NetFirewallRule -DisplayName "$RulePrefix - Allow svchost" -Direction Outbound -Program "$env:SystemRoot\System32\svchost.exe" -Action Allow -Profile Public, Private | Out-Null
Write-Host "  Allowed: svchost.exe (NLA, DNS, DHCP, NCSI)" -ForegroundColor Green

# 6. Allow loopback
New-NetFirewallRule -DisplayName "$RulePrefix - Allow Loopback" -Direction Outbound -RemoteAddress 127.0.0.0/8 -Action Allow -Profile Public, Private | Out-Null
Write-Host "  Allowed: Loopback (127.0.0.0/8)" -ForegroundColor Green

# 7. (Optional) Allow IKE/IPsec to VPN gateway - uncomment and set $VPNGatewayIPs above
# foreach ($ip in $VPNGatewayIPs) {
#     New-NetFirewallRule -DisplayName "$RulePrefix - Allow IKE to $ip" -Direction Outbound -Protocol UDP -RemotePort 500,4500 -RemoteAddress $ip -Action Allow -Profile Public,Private | Out-Null
# }

Write-Host ""
Write-Host "=== Done. Internet is now blocked unless FortiClient VPN is connected. ===" -ForegroundColor Cyan
Write-Host "Run Undo-VPNKillSwitch.ps1 to revert." -ForegroundColor Cyan
