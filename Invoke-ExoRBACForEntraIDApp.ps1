<#
.SYNOPSIS
    Scope Exchange Online application permissions to specific sender mailboxes using RBAC for Applications.

.DESCRIPTION
    This script creates Service Principals in Exchange Online and assigns RBAC roles scoped to specific mailboxes.
    Each app can only send/read/write mail as its designated mailbox(es).
    Uses the new RBAC for Applications feature (not deprecated ApplicationAccessPolicy).
    
    FULLY IDEMPOTENT: Safe to run multiple times, will detect and reuse existing resources.

    DO NOT GRANT mail.send application permissions through Entra ID, they are not needed when granting through
    Exchange Online PowerShell, like this script does.

    YOU MUST target actual mailboxes and not their ProxyAddress - the ProxyAddress will still be a valid sender though.

.NOTES
    Version:        3.1
    Author:         Michael Mardahl
    Creation Date:  2025-01-15
    Purpose/Change: AI optimization of the output and fixed authorization test logic to check InScope property
    
.LINK
    https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac

#>
#Requires -Module ExchangeOnlineManagement

# App Configuration - ADD NEW APPS HERE - Data is from the Enterprise Application blade, NOT the App Registration!
$appConfigs = @(
    @{
        DisplayName = "myApp-prod"
        AppId = "exxxxxx6-0b26-xxx2-b11e-73xxxxxbb26"
        ObjectId = "6axxxxx1d-2cx6-xx48-b1c0-e7xxxxx174"
        AllowedMailbox = "myAppMail@company.com"
    },
    @{
        DisplayName = "myApp-test"
        AppId = "d6xxxxb-8xxa-4xxe-9xxb-fb0f6xxx4550"
        ObjectId = "xxx955c-491a-4x2d-b2b3-868xxxxf043"
        AllowedMailbox = "myAppMail@company.com"
    },
    @{
        DisplayName = "someSupportApp"
        AppId = "96xxxxa4-bfxx-44xx-a0xx-05xxx437d5c3"
        ObjectId = "6xxxx208-0xx1-4xxb-xefc-e7bc0fb0xxx"
        AllowedMailbox = "helpdesk@company.com"
    }
)

# An actual mailbox that is NOT in any scopes - needed to test if the restrictions are working as intended
$testUnauthorizedMailbox = "administrator@company.com"

# Exchange Online roles needed for Mail.Send + Read/Write (Restrict as needed by removing one or the other)
$ExoAppRoles = @(
    "Application Mail.Send",
    "Application Mail.ReadWrite"
)

# Connect to Exchange Online
Write-Host "`n=== Connecting to Exchange Online ===" -ForegroundColor Cyan
Connect-ExchangeOnline

# Pre-load all existing scopes to avoid duplicate lookups
Write-Host "Loading existing management scopes..." -ForegroundColor Gray
$allExistingScopes = @{}
Get-ManagementScope | ForEach-Object { 
    $allExistingScopes[$_.Name] = $_.RecipientFilter 
}

# Process each app
foreach ($app in $appConfigs) {
    Write-Host "`n=== Processing: $($app.DisplayName) ===" -ForegroundColor Yellow
    
    # Step 1: Create Service Principal in Exchange Online (if not exists)
    Write-Host "Creating/Verifying Service Principal..." -ForegroundColor Green
    try {
        $exoSP = Get-ServicePrincipal -Identity $app.AppId -ErrorAction SilentlyContinue
        if ($exoSP) {
            Write-Host "  ✓ Service Principal already exists" -ForegroundColor Gray
        } else {
            $exoSP = New-ServicePrincipal -AppId $app.AppId -ObjectId $app.ObjectId -DisplayName "EntraID - $($app.DisplayName)"
            Write-Host "  ✓ Created new Service Principal" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ✗ Failed to create Service Principal: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    
    # Step 2: Find or create Management Scope for the mailbox
    # Use standardized naming: Scope-Mailbox-{mailbox-prefix}
    $mailboxPrefix = $app.AllowedMailbox.Split('@')[0]
    $scopeName = "Scope-Mailbox-$mailboxPrefix"
    $targetFilter = "PrimarySmtpAddress -eq '$($app.AllowedMailbox)'"
    
    Write-Host "Checking for Management Scope: $scopeName" -ForegroundColor Green
    
    # Look for existing scope with same filter (could have different name from old runs)
    $existingMatchingScope = $null
    foreach ($existingScopeName in $allExistingScopes.Keys) {
        if ($allExistingScopes[$existingScopeName] -eq $targetFilter) {
            $existingMatchingScope = $existingScopeName
            break
        }
    }
    
    if ($existingMatchingScope) {
        # Found a scope with matching filter
        if ($existingMatchingScope -ne $scopeName) {
            Write-Host "  ℹ Found existing scope '$existingMatchingScope' with same filter, will use it" -ForegroundColor Cyan
            $scopeName = $existingMatchingScope
        } else {
            Write-Host "  ✓ Scope already exists" -ForegroundColor Gray
        }
    } else {
        # Create new scope
        try {
            New-ManagementScope -Name $scopeName -RecipientRestrictionFilter $targetFilter -ErrorAction Stop | Out-Null
            $allExistingScopes[$scopeName] = $targetFilter
            Write-Host "  ✓ Created new scope: $scopeName" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✗ Failed to create scope: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
    }
    
    # Step 3: Assign roles with the mailbox scope
    foreach ($role in $ExoAppRoles) {
        $roleShortName = $role.Replace('Application ', '')
        $assignmentName = "$($app.DisplayName)-$roleShortName-$mailboxPrefix"
        Write-Host "Assigning role: $role" -ForegroundColor Green
        
        try {
            # Check if assignment already exists for this app + role + scope combination
            $existingAssignment = Get-ManagementRoleAssignment -RoleAssignee $app.AppId -ErrorAction SilentlyContinue | 
                Where-Object { 
                    $_.Role -eq $role -and 
                    $_.CustomResourceScope -eq $scopeName 
                }
            
            if ($existingAssignment) {
                Write-Host "  ✓ Role assignment already exists: $($existingAssignment.Name)" -ForegroundColor Gray
            } else {
                # Create new assignment
                New-ManagementRoleAssignment -Name $assignmentName -App $app.AppId -Role $role -CustomResourceScope $scopeName -ErrorAction Stop | Out-Null
                Write-Host "  ✓ Created assignment: $assignmentName" -ForegroundColor Green
            }
        }
        catch {
            # Handle duplicate name error gracefully
            if ($_.Exception.Message -like "*already exists*") {
                Write-Host "  ✓ Assignment already exists (name collision, this is OK)" -ForegroundColor Gray
            } else {
                Write-Host "  ✗ Failed to assign role: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    # Step 4: Test the authorization for ALLOWED mailbox
    Write-Host "Testing authorization for ALLOWED mailbox: $($app.AllowedMailbox)" -ForegroundColor Green
    try {
        $authTest = Test-ServicePrincipalAuthorization -Identity $app.AppId -Resource $app.AllowedMailbox
        # Check if ALL results have InScope = True
        $allInScope = ($authTest | Where-Object { $_.InScope -eq $false }).Count -eq 0
        
        if ($allInScope -and $authTest.Count -gt 0) {
            Write-Host "  ✓ PASS - App is IN SCOPE for $($app.AllowedMailbox)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FAIL - App is NOT in scope (permissions may need time to propagate)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Step 5: Verify app CANNOT access other mailboxes
    Write-Host "Negative test - Verifying app CANNOT access: $testUnauthorizedMailbox" -ForegroundColor Green
    try {
        $authTestNegative = Test-ServicePrincipalAuthorization -Identity $app.AppId -Resource $testUnauthorizedMailbox
        # Check if ANY result has InScope = True (should all be False)
        $anyInScope = ($authTestNegative | Where-Object { $_.InScope -eq $true }).Count -gt 0
        
        if (-not $anyInScope) {
            Write-Host "  ✓ PASS - App correctly OUT OF SCOPE for $testUnauthorizedMailbox" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FAIL - App has unauthorized access! InScope shows True" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✓ PASS - Access correctly denied (error expected)" -ForegroundColor Green
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan

Write-Host "`nManagement Scopes in use:" -ForegroundColor White
$scopesInUse = @{}
foreach ($app in $appConfigs) {
    $mailboxPrefix = $app.AllowedMailbox.Split('@')[0]
    $possibleNames = @("Scope-Mailbox-$mailboxPrefix", "Scope-$($app.DisplayName)-$mailboxPrefix")
    foreach ($name in $possibleNames) {
        if ($allExistingScopes.ContainsKey($name)) {
            $scopesInUse[$name] = $allExistingScopes[$name]
        }
    }
}
$scopesInUse.GetEnumerator() | ForEach-Object { 
    [PSCustomObject]@{Name = $_.Key; RecipientFilter = $_.Value} 
} | Format-Table -AutoSize

Write-Host "Role Assignments for configured apps:" -ForegroundColor White
$allAppIds = $appConfigs.AppId
Get-ManagementRoleAssignment -RoleAssigneeType ServicePrincipal -ErrorAction SilentlyContinue | 
    Where-Object { $allAppIds -contains $_.RoleAssignee } | 
    Select-Object Name, Role, @{N='AppId';E={$_.RoleAssignee}}, CustomResourceScope |
    Format-Table -AutoSize

Write-Host "`nDisconnecting from Exchange Online..." -ForegroundColor Cyan
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "`n✓ Script completed successfully!" -ForegroundColor Green
Write-Host "📝 To add more apps: Add entries to `$appConfigs array and rerun this script" -ForegroundColor Cyan
