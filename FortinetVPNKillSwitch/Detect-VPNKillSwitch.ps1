<#
.SYNOPSIS
    Detection script for Intune Win32 package.
    Checks whether the VPN Kill Switch firewall configuration is applied.
.DESCRIPTION
    Returns exit 0 + stdout = Detected (compliant)
    Returns exit 1           = Not detected (non-compliant)
    
    Checks:
    1. All firewall profiles have DefaultOutboundAction = Block
    2. FortiClient allow rules exist in the active policy store
    3. Private IP allow rule exists
    4. svchost allow rule exists
#>

$compliant = $true

# --- Check 1: Default outbound action is Block on all profiles ---
$profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
foreach ($profile in $profiles) {
    if ($profile.DefaultOutboundAction -ne "Block") {
        $compliant = $false
        break
    }
}

# --- Check 2: At least one FortiClient allow rule exists in active store ---
$fortiRules = Get-NetFirewallRule -PolicyStore ActiveStore -Direction Outbound -Action Allow -Enabled True -ErrorAction SilentlyContinue |
    Where-Object {
        $app = ($_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program
        $app -like "*Fortinet*FortiClient*"
    }

if (-not $fortiRules -or $fortiRules.Count -lt 1) {
    $compliant = $false
}

# --- Check 3: Private IP allow rule exists ---
$privateRule = Get-NetFirewallRule -PolicyStore ActiveStore -Direction Outbound -Action Allow -Enabled True -ErrorAction SilentlyContinue |
    Where-Object {
        $addr = ($_ | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue).RemoteAddress
        $addr -contains "10.0.0.0/8" -or $addr -contains "10.0.0.0/255.0.0.0"
    }

if (-not $privateRule) {
    $compliant = $false
}

# --- Check 4: svchost allow rule exists ---
$svchostRule = Get-NetFirewallRule -PolicyStore ActiveStore -Direction Outbound -Action Allow -Enabled True -ErrorAction SilentlyContinue |
    Where-Object {
        $app = ($_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program
        $app -like "*svchost.exe"
    }

if (-not $svchostRule) {
    $compliant = $false
}

# --- Result ---
if ($compliant) {
    Write-Output "VPN Kill Switch firewall configuration detected"
    exit 0
} else {
    exit 1
}
