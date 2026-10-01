<#PSScriptInfo
.VERSION 1.0.0
.AUTHOR Michael Mardahl
.COMPANYNAME Community
.COPYRIGHT (c) Michael Mardahl. All rights reserved.
.TAGS Entra EntraID Licensing GroupBasedLicensing Microsoft365 MicrosoftEntra PowerShell
.PROJECTURI https://github.com/mardahl
.RELEASENOTES
    1.0.0 - Initial release.
#>

<#
.SYNOPSIS
    Removes direct license assignments from members of a license group when the
    same SKU is already applied (Active) through that group.

    Author : Michael Mardahl
    GitHub : https://github.com/mardahl
    Version: 1.0.0

    Shared with the community as-is, without warranty. Test with -WhatIf and a
    small -BatchSize before running in production.

.DESCRIPTION
    Processes a limited batch of users per run (default 10) to allow controlled
    production rollout. Re-running the script picks up the next batch, because
    already-cleaned users no longer qualify.

    Validation steps:
      1. Required modules present and an Entra session with write scope exists.
      2. Target group exists and has licenses assigned.
      3. Per user and SKU:
         - Group-based assignment exists, State = Active, Error = None.
         - Direct assignment exists for the same SKU.
         - Removing the direct assignment does not disable service plans that
           are currently enabled (skipped unless -AllowPlanReduction).
      4. Preview of all planned changes before any write.
      5. Per-user confirmation (ShouldProcess, ConfirmImpact High).
      6. Post-change verification: direct assignment gone AND group assignment
         still Active. Any failure halts the run immediately.

    All decisions are written to a CSV log.

.PARAMETER GroupId
    Object ID of the license group.

.PARAMETER BatchSize
    Maximum number of users changed in one run. Default 10, max 50.

.PARAMETER SkuId
    Optional. Limit processing to one SKU (GUID). Default: all SKUs on the group.

.PARAMETER AllowPlanReduction
    Remove direct assignment even when the group assignment has more service
    plans disabled than the direct assignment.

.PARAMETER LogPath
    CSV log path. Default: .\DirectLicenseRemoval_<timestamp>.csv

.EXAMPLE
    .\Remove-DirectLicenseCoveredByGroup.ps1 -GroupId <groupObjectId> -WhatIf

.EXAMPLE
    .\Remove-DirectLicenseCoveredByGroup.ps1 -GroupId <groupObjectId> -BatchSize 10

.NOTES
    Author : Michael Mardahl (https://github.com/mardahl)
    Version: 1.0.0

    Requires: Microsoft.Entra (Users, Groups) and Microsoft.Graph.Authentication
              (installed as a Microsoft.Entra dependency).
    Delegated scopes: User.ReadWrite.All (or LicenseAssignment.ReadWrite.All), Group.Read.All
    Roles: License Administrator, User Administrator or Directory Writers.

    Known issues / limitations
    - Only direct group members are evaluated. Group-based licensing does not
      flow through nested groups.
    - Service plan comparison uses disabledPlans from licenseAssignmentStates.
      Plans enabled by OTHER groups for the same SKU are counted as covered.
    - licenseAssignmentStates is read via Invoke-MgGraphRequest for reliable
      raw property access.
    - Removal is not automatically reversible. The CSV log contains the
      removed SKU IDs and the original disabledPlans for manual rollback
      with Set-EntraUserLicense.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$GroupId,

    [ValidateRange(1, 50)]
    [int]$BatchSize = 10,

    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SkuId,

    [switch]$AllowPlanReduction,

    [string]$LogPath = (Join-Path -Path (Get-Location) -ChildPath ("DirectLicenseRemoval_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date)))
)

$ErrorActionPreference = 'Stop'
$log = [System.Collections.Generic.List[object]]::new()

function Write-Log {
    param($Upn, $UserId, $Sku, $Action, $Detail, $DirectDisabledPlans = '')
    $entry = [pscustomobject]@{
        Timestamp           = (Get-Date).ToString('s')
        UserPrincipalName   = $Upn
        UserId              = $UserId
        SkuId               = $Sku
        Action              = $Action
        Detail              = $Detail
        DirectDisabledPlans = $DirectDisabledPlans
    }
    $log.Add($entry)
    $entry | Export-Csv -Path $LogPath -NoTypeInformation -Append -Encoding UTF8
}

function Get-UserLicenseState {
    param([string]$UserId)
    $uri = "https://graph.microsoft.com/v1.0/users/$UserId`?`$select=id,userPrincipalName,licenseAssignmentStates"
    Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject
}

#region Step 1 - Module and session validation
Write-Host "[1/6] Validating modules and session..." -ForegroundColor Cyan
foreach ($m in 'Microsoft.Entra.Users', 'Microsoft.Entra.Groups', 'Microsoft.Graph.Authentication') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        throw "Module '$m' not found. Install with: Install-Module Microsoft.Entra -Scope CurrentUser"
    }
}

$ctx = Get-EntraContext
if (-not $ctx) {
    throw "No Entra session. Run: Connect-Entra -TenantId <tenant> -Scopes 'User.ReadWrite.All','Group.Read.All'"
}
$writeScopes = 'User.ReadWrite.All', 'LicenseAssignment.ReadWrite.All', 'Directory.ReadWrite.All'
if (-not ($ctx.Scopes | Where-Object { $_ -in $writeScopes })) {
    throw "Session lacks a license write scope. Current scopes: $($ctx.Scopes -join ', ')"
}
Write-Host "  Tenant : $($ctx.TenantId)"
Write-Host "  Account: $($ctx.Account)"
#endregion

#region Step 2 - Group validation
Write-Host "[2/6] Validating group..." -ForegroundColor Cyan
$group = Invoke-MgGraphRequest -Method GET -OutputType PSObject `
    -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId`?`$select=id,displayName,assignedLicenses"

if (-not $group.assignedLicenses -or $group.assignedLicenses.Count -eq 0) {
    throw "Group '$($group.displayName)' has no licenses assigned. Aborting."
}

$groupSkus = @($group.assignedLicenses.skuId)
if ($SkuId) {
    if ($SkuId -notin $groupSkus) { throw "SKU $SkuId is not assigned to group '$($group.displayName)'." }
    $groupSkus = @($SkuId)
}

$skuNames = @{}
Get-EntraSubscribedSku | ForEach-Object { $skuNames[[string]$_.SkuId] = $_.SkuPartNumber }

Write-Host "  Group: $($group.displayName)"
$groupSkus | ForEach-Object { Write-Host "  SKU  : $_ ($($skuNames[$_]))" }
#endregion

#region Step 3 - Candidate evaluation
Write-Host "[3/6] Evaluating members (batch limit $BatchSize)..." -ForegroundColor Cyan
$members = Get-EntraGroupMember -GroupId $GroupId -All |
    Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' -or $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' }

Write-Host "  User members: $(@($members).Count)"
$candidates = [System.Collections.Generic.List[object]]::new()

foreach ($member in $members) {
    if ($candidates.Count -ge $BatchSize) { break }

    $user = Get-UserLicenseState -UserId $member.Id
    $states = @($user.licenseAssignmentStates)
    $removeSkus = @()
    $directPlanInfo = @()

    foreach ($sku in $groupSkus) {
        $direct = $states | Where-Object { $_.skuId -eq $sku -and [string]::IsNullOrEmpty($_.assignedByGroup) }
        if (-not $direct) { continue }

        $viaThisGroup = $states | Where-Object { $_.skuId -eq $sku -and $_.assignedByGroup -eq $GroupId }
        if (-not $viaThisGroup -or $viaThisGroup.state -ne 'Active' -or ($viaThisGroup.error -and $viaThisGroup.error -ne 'None')) {
            Write-Log $user.userPrincipalName $user.id $sku 'Skipped' "Group assignment not Active (State=$($viaThisGroup.state); Error=$($viaThisGroup.error))"
            continue
        }

        # Plans disabled by ALL active group assignments for this SKU = effective group-disabled set
        $activeGroupStates = @($states | Where-Object {
            $_.skuId -eq $sku -and -not [string]::IsNullOrEmpty($_.assignedByGroup) -and $_.state -eq 'Active' })
        $groupDisabled = @($activeGroupStates[0].disabledPlans)
        foreach ($g in $activeGroupStates | Select-Object -Skip 1) {
            $groupDisabled = @($groupDisabled | Where-Object { $_ -in @($g.disabledPlans) })
        }
        $directDisabled = @($direct.disabledPlans)
        $lostPlans = @($groupDisabled | Where-Object { $_ -notin $directDisabled })

        if ($lostPlans.Count -gt 0 -and -not $AllowPlanReduction) {
            Write-Log $user.userPrincipalName $user.id $sku 'Skipped' "Removal would disable plans: $($lostPlans -join ';')" ($directDisabled -join ';')
            continue
        }

        $removeSkus += $sku
        $directPlanInfo += "$sku=[$($directDisabled -join ';')]"
    }

    if ($removeSkus.Count -gt 0) {
        $candidates.Add([pscustomobject]@{
            UserId              = $user.id
            UserPrincipalName   = $user.userPrincipalName
            RemoveSkus          = $removeSkus
            RemoveSkuNames      = ($removeSkus | ForEach-Object { $skuNames[$_] }) -join ', '
            DirectDisabledPlans = $directPlanInfo -join ' '
        })
    }
}

if ($candidates.Count -eq 0) {
    Write-Host "No users qualify for direct license removal. Log: $LogPath" -ForegroundColor Green
    return
}
#endregion

#region Step 4 - Preview
Write-Host "[4/6] Planned changes ($($candidates.Count) users):" -ForegroundColor Cyan
$candidates | Format-Table UserPrincipalName, RemoveSkuNames -AutoSize | Out-String | Write-Host
#endregion

#region Step 5 + 6 - Apply with confirmation and verify
Write-Host "[5/6] Applying changes..." -ForegroundColor Cyan
$changed = 0

foreach ($c in $candidates) {
    $target = "$($c.UserPrincipalName) - remove direct: $($c.RemoveSkuNames)"
    if (-not $PSCmdlet.ShouldProcess($target, 'Remove direct license assignment')) {
        Write-Log $c.UserPrincipalName $c.UserId ($c.RemoveSkus -join ';') 'NotApplied' 'WhatIf or declined' $c.DirectDisabledPlans
        continue
    }

    try {
        $licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
        $licenses.RemoveLicenses = [string[]]$c.RemoveSkus
        Set-EntraUserLicense -UserId $c.UserId -AssignedLicenses $licenses | Out-Null
    }
    catch {
        Write-Log $c.UserPrincipalName $c.UserId ($c.RemoveSkus -join ';') 'Failed' "Set-EntraUserLicense: $($_.Exception.Message)" $c.DirectDisabledPlans
        throw "Removal failed for $($c.UserPrincipalName). Run halted. Log: $LogPath"
    }

    # Verification with retry (license processing can lag)
    Write-Host "[6/6] Verifying $($c.UserPrincipalName)..." -ForegroundColor Cyan
    $verified = $false
    for ($i = 1; $i -le 6 -and -not $verified; $i++) {
        Start-Sleep -Seconds 5
        $after = @((Get-UserLicenseState -UserId $c.UserId).licenseAssignmentStates)
        $ok = $true
        foreach ($sku in $c.RemoveSkus) {
            $directLeft = $after | Where-Object { $_.skuId -eq $sku -and [string]::IsNullOrEmpty($_.assignedByGroup) }
            $groupOk    = $after | Where-Object { $_.skuId -eq $sku -and $_.assignedByGroup -eq $GroupId -and $_.state -eq 'Active' }
            if ($directLeft -or -not $groupOk) { $ok = $false }
        }
        $verified = $ok
    }

    if (-not $verified) {
        Write-Log $c.UserPrincipalName $c.UserId ($c.RemoveSkus -join ';') 'VerifyFailed' 'Direct still present or group assignment not Active after 30s' $c.DirectDisabledPlans
        throw "Verification failed for $($c.UserPrincipalName). Run halted. Log: $LogPath"
    }

    Write-Log $c.UserPrincipalName $c.UserId ($c.RemoveSkus -join ';') 'Removed' 'Verified: direct removed, group assignment Active' $c.DirectDisabledPlans
    Write-Host "  OK: $($c.UserPrincipalName)" -ForegroundColor Green
    $changed++
}
#endregion

Write-Host "Done. Users changed: $changed / $($candidates.Count). Log: $LogPath" -ForegroundColor Green
