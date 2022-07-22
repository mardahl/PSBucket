#Script to disable user accounts that have expired so they cannot login via Azure AD.
#Published on github by Michael Mardahl (github.com/mardahl)
#inspired/improved from - https://blog.blksthl.com/2021/04/13/expired-accounts-remains-active-in-azure-ad/
#Should be run with least privileged gMSA account as scheduled task. (read-userAccountControl, write-userAccountControl in AD)

#Requires -Modules ActiveDirectory

#region declarations
$LogPath = 'C:\Scripts\DisableExpiredAccounts'
#endregion declarations

#region static
$Now = Get-date
$day = Get-date -Format dddd
#endregion static

#region log
#init log file - clear out the old and just keep one log file for each day of the week.
(Get-Date -Format "yyyy-MM-dd HH:mm").ToString() + " | " + "Initialized logfile" | Out-File $LogPath\ExpiredUserLog_$day.txt -force

function LogToFile ($LogPath, $LogText){
    if(-not (Test-Path $LogPath)){
        New-Item -ItemType Directory -Force -Path $LogPath
    }
    (Get-Date -Format "yyyy-MM-dd HH:mm").ToString() + " | " + $LogText | Out-File $LogPath\ExpiredUserLog_$day.txt -Append -force
}
#endregion log

#region evaluate
$AllUsers = Search-ADAccount -AccountExpired -UsersOnly | Where-Object {$_.Enabled} | sort SamAccountName

if ($AllUsers.count -gt 0){
    LogToFile $LogPath ("Number of expired users found: "+ $AllUsers.Count)
} else {
    LogToFile $LogPath ("Number of expired users found: "+ $AllUsers.Count)
    LogToFile $LogPath ("Script execution halted")
    exit 0
}
#endregion evaluate

#region execute
foreach($User in $AllUsers){
    $UserExpiryDate = (Get-Date ($User.accountExpirationDate) -Format "yyyy-MM-dd HH:mm").ToString()
    try{
        #Disable the account
        Disable-ADAccount $User.SamAccountName
        LogToFile $LogPath ("Expired on: " + $UserExpiryDate + " | Disabled: " + $User.UserPrincipalName + " - " + $User.DisplayName)
    } catch {
        # If disable failed, log
        $ThisError = $Error[0]
        LogToFile $LogPath ("Expired on: " + $UserExpiryDate + " | User: " + $User.UserPrincipalName + " - " + $User.DisplayName + " - - - ERROR!")
        LogToFile $LogPath ("ERROR message:" + $ThisError)
    }
}
LogToFile $LogPath ("Script execution completed") 
#endregion execute
