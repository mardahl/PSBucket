<#
.SYNOPSIS
    Cleaup of stale and non-compliant "registered" devices in Azure AD for tenants using Intune to manage devices

.DESCRIPTION
    This script will find all devices that are "workplace Joined" in Azure AD, and compare them to all Intune managed devices.
    If a device is not found in Intune, it will be disabled.
    On the next run of the script, it will be removed if it last communicated with Intune over 40 days ago (adjustable).

.INPUTS
  None

.OUTPUTS
  Log file stored in .\log.txt

.NOTES
  Version:        1.0b
  Author:         Michael Mardahl
  Twitter: @michael_mardahl
  Blogging on: www.msendpointmgr.com
  Creation Date:  03 August 2020
  Purpose/Change: Initial script development

.EXAMPLE
  .\CleanupWPJNotInIntune.ps1
  (Needs to be executed interactively)

.NOTES
  Requires the following modules to be installed:
  MSOnline
  microsoft.graph.intune

#>
#Requires -Modules MSOnline, microsoft.graph.intune

#region declarations

#Number of days in which the device has not checked in, but will be allowed to exist in AAD alone.
[int]$GracePeriod = 40

#endregion declarations

#region execute

#Start log
Start-Transcript .\log.txt -Force

#Connecting to cloud services interactively
Connect-MsolService
Connect-MSGraph

#region find devices
$intuneDevices = Get-IntuneManagedDevice -ErrorAction Stop | Select-Object azureADDeviceId, DeviceName, UserPrincipalName
$AADdevices = Get-MsolDevice -all -ErrorAction Stop | select-object -Property Enabled, DeviceId, DisplayName, DeviceTrustType, ApproximateLastLogonTimestamp, DeviceOSType, DeviceTrustLevel
$wordplaceJoined = $AADdevices | Where-Object DeviceTrustType -EQ "Workplace Joined" | Where-Object Enabled -EQ $false | sort ApproximateLastLogonTimestamp
$notInIntune = @()

Write-Verbose "Generating list of devices in AAD that dont exist in Intune" -Verbose
Foreach ($device in $wordplaceJoined) {
    #Write-Host "$($device.DisplayName) - $(get-date ($device.ApproximateLastLogonTimestamp) -f ddd-MMM-yyyy) : " -ForegroundColor Yellow -NoNewline
    $intuneTest =  $intuneDevices | Where-Object azureADDeviceId -EQ $device.DeviceId
    
    if($intuneTest) {
        #Write-Host $intuneTest.UserPrincipalName -ForegroundColor Green
    } else {
        #Write-Host "Not in Intune!" -ForegroundColor Red
        $notInIntune += $device
    }
}
#endregion find devices

#region disable devices
Write-Verbose "Disabling abandoned devices" -Verbose
Read-Host "Press enter to continue..."
#Disable abandoned devices
foreach ($staleDevice in $notInIntune) {
    
    Disable-MsolDevice -DeviceId $staleDevice.DeviceId -Verbose -Force
    Write-Host "Disabled: $($staleDevice.DisplayName)" -ForegroundColor Yellow
}

#endregion disable devices


#region remove devices
Write-Verbose "Removing stale disabled devices." -Verbose
Read-Host "Press enter to continue..."
#Define grace period marker date
$graceDate = (Get-Date).AddDays(-$GracePeriod)

#Get list of devices to be removed based on our grace period marker date
$disable = $AADdevices | Where-Object Enabled -EQ $false | Where-Object ApproximateLastLogonTimestamp -LT $graceDate

#Remove disabled devices
foreach ($disabledDevice in $disable) {
    Write-Host "Removing $($disabledDevice.DisplayName)." -ForegroundColor Yellow
    Remove-MsolDevice -DeviceId $disabledDevice.DeviceId -Verbose -Force
}

#endregion remove devices

Stop-Transcript
#endregion execute
