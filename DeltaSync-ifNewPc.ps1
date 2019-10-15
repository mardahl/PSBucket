#Requires -RunAsAdministrator
#Requires -module ActiveDirectory
<#
.SYNOPSIS
This script will start a delta sync on the Azure AD Connect server
.DESCRIPTION
Quick script that looks for a newly create computer object in local AD, then makes sure it's ready to sync with AAD
.EXAMPLE
Just run this script without any parameters as an admin account og the server hosting the AAD Connect tool
.NOTES
NAME: DeltaSync-ifNewPC.ps1
VERSION: 1910.1
PREREQ: ActiveDirectory PowerShell module
.COPYRIGHT
@michael_mardahl / https://www.iphase.dk
Licensed under the MIT license.
Please credit me if you fint this script useful and do some cool things with it.
#>

### Config section

# configure computers OU search base (this is where the devices you want to sync with AAD reside).
$computersOU = "OU=MyComputers,DC=domain,DC=local"

### Script execution

# Examining the specified computers OU. Determining if there was added a new device within the last hour
Write-Host "Searching for newly joined computers. Starting AAD Sync as soon as the computers have a UserCertificate populated..." -ForegroundColor Cyan

$allClear = $false
DO{

    $computers = Get-ADComputer -SearchBase $computersOU -filter * -Properties UserCertificate,WhenCreated -searchscope subtree | Where-Object {$_.WhenCreated -gt ((get-date).AddHours(-1))}

    if ($computers.PropertyCount -lt 1) { 
        Write-Host "Found 0 new computer objects!" -ForegroundColor Yellow
        pause
        exit
    }

    foreach ($computer in $computers) {
    
        #Determining if the computer has a UserCertificate, otherwise there is no reason to run AAD Connect DeltaSync just yet....
        if($($computer.UserCertificate) -gt 0) {
            Write-Host "$($Computer.Name) has a UserCertificate" -ForegroundColor Green
        } else {
            Write-Host "$($Computer.Name) is missing a UserCertificate" -ForegroundColor Yellow
            $missingCert = $true
        }

    }

    if($missingCert){
        Write-Host "Waiting a minute to check again..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
    } else {
        Write-Host "All looks good, starting delta sync." -ForegroundColor Green

        DO{
            try {
                $synctask = Start-ADSyncSyncCycle -PolicyType delta -ErrorAction stop
                $syncOK = $true
            } catch {
                $syncOK = $false
                Write-Host "Sync service busy! Waiting 30 seconds..." -ForegroundColor DarkYellow
            }

            Start-Sleep -Seconds 30
        
        }WHILE($syncOK -ne $true)
        
        $allClear = $true
    }

} WHILE ($allClear -ne $true)

Write-Host "Done!" -ForegroundColor Green
pause
