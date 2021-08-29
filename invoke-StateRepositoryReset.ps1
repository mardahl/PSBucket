<#
.SYNOPSIS
    Resets the StateRepository Database.
.DESCRIPTION
    The StateRepository database is used by the StateRepository service which is in turn used by the AppReadiness and AppXsvc services.
    This script attempts to stop the services and delete the database files, which will the be recreated automatically.
.INPUTS
    None
.NOTES
    Version       : 1.0
    Author        : Michael Mardahl
    Twitter       : @michael_mardahl
    Blogging on   : www.msendpointmgr.com
    Creation Date : August 29th 2021
    Purpose/Change: Initial script
    License       : MIT (Leave author credits)
.EXAMPLE
    Execute script as SYSTEM
    .\invoke-StateRepositoryReset.ps1
.NOTES
    Remember to take backups of your servers before running this thing on a regular basis.
    The script outputs a log file to C:\TEMP\last_StateRepositoryResetLog.txt
#>

#requires -RunAsAdministrator

Start-Transcript C:\TEMP\last_StateRepositoryResetLog.txt

Write-Verbose "Resetting StateRepository Databases for AppX / App Readiness" -Verbose
Write-Verbose "Attempting to stop StateRepository service" -Verbose

$retry = 3
DO{
    Get-Service -Name StateRepository | Stop-Service -Force
    Start-Sleep 1
    Get-Service -Name AppReadiness | Stop-Service -Force
    Start-Sleep 1
    $retry--
} While (
    ((Get-Service -Name StateRepository).Status -ne "Stopped") -and ($retry -gt 0)
)

if ((Get-Service -Name StateRepository).Status -eq "Stopped") {
    Write-Verbose "StateRepository service is stopped" -Verbose
    Write-Verbose "Attempting to delete old StateRepository database files..." -Verbose
    del C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository*
    Write-Verbose "Done. Starting StateRepository Service" -Verbose
    Get-Service -Name StateRepository | Start-Service
} else {
    Write-Verbose "StateRepository service failed to stop! Terminating." -Verbose
}
Stop-Transcript
