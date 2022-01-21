# Enable User Experience Virtualization
try {
    Enable-Uev
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message ; break
}
# Set variables
$UEVStatus = Get-UevStatus
$TemplateDir = "$env:ALLUSERSPROFILE\Microsoft\UEV\InboxTemplates\"
$TemplateArray = "DesktopSettings2013.xml","MicrosoftNotepad.xml","MicrosoftOffice2016Win32.xml","MicrosoftOffice2016Win64.xml","MicrosoftOutlook2016CAWin32.xml","MicrosoftOutlook2016CAWin64.xml","MicrosoftWordpad.xml"
# Configure UEV
if ($UEVStatus.UevEnabled -eq "True") {
    # Set sync to wait for logon and start of applications
    Set-UevConfiguration -Computer -EnableWaitForSyncOnApplicationStart -EnableWaitForSyncOnLogon
    # Set SyncMethod to External - for use with OneDrive
    Set-UevConfiguration -Computer -SyncMethod External
    # Set the Storagepath to OneDrive
    Set-UevConfiguration -Computer -SettingsStoragePath %OneDrive%
    # Do not synchronize any Windows apps settings for all users on the computer. Use Azure AD Enterprise State Roaming instead.
    Set-UevConfiguration -Computer -EnableDontSyncWindows8AppSettings
    # Do not display notification the first time that the service runs for all users on the computer.
    Set-UevConfiguration -Computer -DisableFirstUseNotification
    # Do not sync any Windows apps (UWP) for all users on the computer
    Set-UevConfiguration -Computer -DisableSyncUnlistedWindows8Apps
    foreach ($Template in $TemplateArray) {
        try { 
            Register-UevTemplate -LiteralPath $TemplateDir\$Template
        }
        catch [System.Exception]
            {
            Write-Warning -Message $_.Exception.Message ; break
        }
    }
}
