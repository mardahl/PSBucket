#AD Stale computer Object cleanup script
#Should be run as a scheduled task with a gMSA account that has permissions to read computer object attributes and modify/delete them.
#The computer it runs on must have RSAT installed for the ActiveDirectory module to be loaded.
#Suggestion is to run two instances of this script, one for servers and one for workstations

#Requires -Module ActiveDirectory
#Requires -RunAsAdministrator



#####Config

#Where to find computer objects (recursive)
$OUs = "OU=Windows 10,OU=Computers,DC=domain,DC=com"

#Inactivity threshhold
$DaysInactive = 60 

#Where to moved inactive objects
$TargetOU = "OU=Inactive,OU=Computers,DC=domain,DC=com"

#Email SMTP variables
$SMTPUsername = "anonymous"
$SMTPPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
$SMTPCredentials = New-Object System.Management.Automation.PSCredential($SMTPUsername,$SMTPPassword)
$SMTPServer = "smtp.domain.com”
$To = "helpdesk@domain.com"
$bcc = "sysadmin@domain.com"
$From = "Active Directory Monitor <ADMonitor@domain.com>"
$Subject = "Inactive Computers (Workstation) objects $(get-date -f ddMMyyyy)"


#####Execution

#Start logging...
$path = Get-Location
$scriptName = $MyInvocation.MyCommand.Name
$scriptLog = "$path\LOG_$scriptName.txt"
Start-Transcript -Path $scriptLog -Force -ErrorAction Stop

#What computers, OUs and the age of objects to find
$Time = (Get-Date).Adddays(-($DaysInactive))
$Today = Get-Date 
$Description = "Account disabled due to inactivity on $Today" 
$Computers = foreach ($OU in $OUs){Get-ADComputer -SearchBase $OU -SearchScope 'Subtree' -Filter {LastLogonTimeStamp -lt $Time} -Properties LastLogonTimeStamp | Select-Object Name,DistinguishedName}

# Creating initial email body area, including stylesheet
$Body = @"
<html>
    <head>
        <style type='text/css'>
        h1 {
            color: #f07f13;
            font-family: verdana;
            font-size: 20px;
        }

        h2 {
            color: ##002933;
            font-family: verdana;
            font-size: 15px;
        }

        body {
            color: #002933;
            font-family: verdana;
            font-size: 13px;
        }
        </style>
    </head>
    <body>
        <h1>Inactive Computer Objects</h1>
        <p>The following computers have been inactive for more than $DaysInactive days and is being disabled and moved to:</p>
        <ul><li>{0}</li></ul>
        <hr/>
        <ul>
"@ -f $TargetOU

#Building body text for email contents
foreach ($Computer in $Computers) {

    if ($Computer.DistinguishedName -notlike "*$TargetOU") {

        Write-Verbose "Working on" $Computer.Name -Verbose
    
        try {
            Set-ADComputer -Identity $Computer.Name -Enabled $false -Description $Description
            Move-ADObject -Identity $Computer.DistinguishedName -TargetPath $TargetOU
            Write-Verbose "Succesfully moved and disabled $($Computer.Name)" -Verbose
            $Body += "<li>$($Computer.Name)</li>"
        }
        catch {
            Write-Error "$($Computer.Name) could not be moved"
            $Body += "<li><font color=red>$($Computer.Name) - COULD NOT BE MOVED!</font></li>"
            continue
        }
    } else {
        Write-Host -ForegroundColor Cyan "$($Computer.Name) has already been moved - doing nothing"
    }
}

#Change email body if there where inactive computers or not
if ($Computers -eq $null){

$Body += @"
<h2><font color=green>No inactive computers this week - how great is that? :)</font></h2>
</body>
</html>
"@
    Write-Verbose "No inactive computers" -Verbose

} else {

$Body += @"
</ul>
<hr/>
</body>
</html>
"@

}

#Sending email message

try {
    Write-Verbose "Sending email to $To and $bcc..." -Verbose
    Send-MailMessage -To $To -From $From -Bcc $bcc -Subject $Subject -Body $Body -smtpServer $SMTPServer -BodyAsHtml -Credential $SMTPCredentials -ErrorAction Stop
} catch {
    $Error
    Throw "Could not send email!"
    Stop-Transcript
    exit 1
}

Write-Verbose "Finished..." -Verbose
#Stop logging
Stop-Transcript
