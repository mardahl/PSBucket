#Quick and dirty script to fix "The group policy client service failed the sign-in" Access denied due to unexpected app instance reference count
#https://techcommunity.microsoft.com/t5/azure-virtual-desktop/wvd-logon-issues-the-group-policy-client-service-failed-the-sign/m-p/1876481
#by Michael Mardahl github.com/mardahl

#requires -RunAsAdministrator

#region declarations

$resetAll = $false #set this to $true to simply reset the refCount on ALL profiles! - use with caution!

#endregion declarations

#region execute
Start-Transcript C:\TEMP\last_ProfileServiceReferences_CleanupLog.txt -force

Write-Information "Resetting ProfileService References for users not signed in and possibly abandoned..."

#region userSID

#Get SID all users logged into the session host
$currentUsersName = Get-Process -IncludeUserName | Select-Object UserName | Where-Object { $_.UserName -ne $null } | Sort-Object UserName -Unique

#Get SID's of logged in users
$currentUsersSID = @()
foreach ($nameObj in $currentUsersName) {
    $curUserObj = $nameObj.UserName -split "\\"
    $curUserdomain = $curUserObj[0]
    $curUserName = $curUserObj[1]
    #add SID to array
    $currentUsersSID += (Get-CimInstance -Class Win32_UserAccount -Filter "Domain = '$curUserdomain' AND Name = '$curUserName'").SID
}
#Check to see if we found some user sessions, otherwise skip, since there might be something wrong if there are absolutely no sessions running - or we might just have rebooted.
If ($currentUsersSID.count -lt 1) {
    Write-Information "Found no active users on the system, exiting out of caution."
    exit 0
} else {
    Write-Information "Found $($currentUsersSID.count) active users on the system."
}
#endregion userSID

#region folderSID

#Find abandoned FSLogix local profile folders username
Push-Location $env:Public
cd ..
$localFoldersObj = Get-ChildItem . | Where-Object { $_.Name -like "local_*" }
Pop-Location

#Get SID's of abandoned users
$abandonedUsersSID = @()
foreach ($nameObj in $localFoldersObj) {
    $curUserObj = $nameObj.Name -split "_"
    $curUserName = $curUserObj[1]
    #add SID to array if not in list of active users
    $curSID = (Get-CimInstance -Class Win32_UserAccount -Filter "Name = '$curUserName'").SID
    if ($currentUsersSID -icontains $curSID) {
        Write-Information "$curUserName ($curSID) is signed in - skipping"
    } else {
        Write-Information "$curUserName ($curSID) is not signed in - marking for cleanup"
        $abandonedUsersSID += $curSID
    }
}
#Check to see if we found some abandoned user sessions, otherwise skip, since there might not be any cleanup needed.
If ($abandonedUsersSID.count -lt 1) {
    Write-Information "Found no indication of abandoned users on the system, skipping cleanup"
    exit 0
} else {
    Write-Information "Found $($abandonedUsersSID.count) possible abandoned users local folders on the system."
}
#endregion folderSID

#region refCountCleanup

#validate the ProfileServices References path in registry
$ProfileServiceReferencesPath  = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileService\References"
If (-not (Test-Path $ProfileServiceReferencesPath)) {
    Write-Error "Path not found: $ProfileServiceReferencesPath"
    exit 1
}

#Get all registry items from path
$usersRefObj = Get-ChildItem $ProfileServiceReferencesPath

#Process all profile service reference registry entries individually
foreach ($refItem in $usersRefObj) {
    
    #check to see if we need to reset refcount, if we have not forced the reset of all
    if($resetAll -eq $false){
        #Check current registry item for a match with the abandoned users SID.
        If ($abandonedUsersSID -icontains $refItem.PSChildName) {
            Write-Information "$($refItem.PSChildName) was marked for cleanup - resetting RefCount"
        } else {
            #skip current registry item
            continue
        }
    } else {
        Write-Information "Reset all switch active! - forcing reset"
    }

    #Check that path exists in registry and reset the RefCount
    If (Test-Path $refItem.PSPath) {
        Set-ItemProperty -Path $($refItem.PSPath) -Name RefCount -Value 0
        Write-Information "Reset the RefCount in: $($refItem.PSPath)"
    }
    

}
#endregion RefCountCleanup

Write-Information "Completed cleanup process"
Stop-Transcript
#endregion execute
