#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reverts the VPN kill switch firewall configuration.
.DESCRIPTION
    Removes all firewall rules created by Setup-VPNKillSwitch.ps1
    and restores the original default outbound action per profile.
#>

$ErrorActionPreference = "Stop"
$RulePrefix = "VPNKillSwitch"
$savedStatePath = "$env:ProgramData\VPNKillSwitch_SavedState.xml"

Write-Host "=== VPN Kill Switch Undo ===" -ForegroundColor Cyan

# 1. Remove all kill switch firewall rules
$rules = Get-NetFirewallRule -DisplayName "$RulePrefix*" -ErrorAction SilentlyContinue
if ($rules) {
    $rules | Remove-NetFirewallRule
    Write-Host "Removed $($rules.Count) kill switch firewall rule(s)." -ForegroundColor Green
} else {
    Write-Host "No kill switch rules found." -ForegroundColor Yellow
}

# 2. Restore original default outbound action
if (Test-Path $savedStatePath) {
    $savedState = Import-Clixml -Path $savedStatePath
    foreach ($profile in $savedState) {
        Set-NetFirewallProfile -Profile $profile.Name -DefaultOutboundAction $profile.DefaultOutboundAction
        Write-Host "Restored $($profile.Name) profile -> DefaultOutbound: $($profile.DefaultOutboundAction)" -ForegroundColor Green
    }
    Remove-Item $savedStatePath -Force
    Write-Host "Removed saved state file."
} else {
    # No saved state — assume the safe default (Allow)
    Write-Host "No saved state found. Resetting all profiles to DefaultOutbound: Allow" -ForegroundColor Yellow
    Set-NetFirewallProfile -Profile Domain, Public, Private -DefaultOutboundAction Allow
}

Write-Host ""
Write-Host "=== Done. Firewall restored to previous state. ===" -ForegroundColor Cyan
