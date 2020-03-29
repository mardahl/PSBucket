#Requires -module ActiveDirectory
#Requires -version 5.0
<#
.SYNOPSIS
Script to monitor and alert on computer objects in Active Directory with missing AppLocker policy assignement
.DESCRIPTION
This script will compare a list of Computers within all the specified Organisational Units, with two AppLocker assignemnt Security Groups.
The groups should include all those computer that have enforced AppLocker policies and those that are Exempt from the policies.
If you have alot of different groups, you can have multiple copies of this script running for each of the assignmetn types that your organisation uses.
.REQUIREMENTS
This script requires the Active Directory PowerShell module which can be obtained by installing the RSAT windows feature.
The script must be run by an account that has network access to enumerate computers and group members in active directory, specifically those that are configured in this script.
The account must also have access to relay email messages through the specified SMTP server, unless it acts as an open relay.
a Managed Service Account is prefered for security reasons.
.EXAMPLE
Testing the script requires that you have gone through the configuration section and modified it to fit your environment.
You can test the script just by running it, to analyze the output and make sure everything works.
.INSTALLATION
Running the script from a scheduled task:
    Configure a scheduled task to run: powershell.exe
    Fill out the "start in" folder to be the directory where you have stored this script.
    Fill in these commandline arguments: -ex bypass -file AppLocker-Monitor.ps1
.VERSION
1910.2
.COPYRIGHT
MIT License, feel free to distribute and use as you like, please leave author information.
.AUTHOR
Michael Mardahl - @michael_mardahl on twitter - BLOG: https://www.iphase.dk
.DISCLAIMER
This script is provided AS-IS, with no warranty - Use at own risk!
#>


############################################################################################
# 
# CONFIG SECTION
#
############################################################################################

# Log file name and location
$LogFile = ".\AppLocker-Monitor_last_run_log.txt"

# SMTP server for sending (the account running this script will get credentials passed to this SMTP server)
$PSEmailServer = 'smtp.outlook.com'
# Alert "from" address
$Emailfrom = 'AppLocker Monitor <applocker-monitor@tenant.onmicrosoft.com>'
# Recipient array
$Recipients = "Peter Griffin <thegriffster@tenant.onmicrosoft.com","IT Security <cybersec@tenant.onmicrosoft.com>"
# AD group containing computers with AppLocker Enforcement
$IncludeACL = "acl_applocker_enforcement"
# AD group containing computers EXEMPTED from the above groups policy (computers can exist in both if your GPO scope is correctly configured)
$ExcludeACL = "acl_applocker_exemption"
# Array of organisational Units containing all computers that should be evaluated for AppLocker membership in the above groups (recursive!)
$OUs = "Computers", "Desktops", "Laptops"


############################################################################################
#
# FUNCTIONS SECTION
#
############################################################################################

Build-ReferenceArray {
    $OUMembers = @() # initialising object array
    Write-Output "[$((Get-Date).TimeOfDay)] Building reference object array from Organisational Unit computer objects..."

    # Get computers in configured Organisational Unit
    foreach ($OU in $OUs) {
        Write-Output "[$((Get-Date).TimeOfDay)] Collecting computers from OU named ""$OU"""
        try {
            $OUObj = Get-ADOrganizationalUnit -Filter 'name -eq $OU'
            $OUMembers += Get-ADComputer -Filter * -SearchBase $OUobj.DistinguishedName
        } catch {
            Write-Error "$OU not found!"
            continue
        }
    }
    return $OUMembers
}

Build-DifferenceArray {
    Write-Output "[$((Get-Date).TimeOfDay)] Building difference object array from AppLocker Security Groups..."

    # Get include group members
    Write-Output "[$((Get-Date).TimeOfDay)] Collecting computers from OU named ""$IncludeACL"""
    try {
        $GroupMembers = Get-ADGroupMember -Identity $IncludeACL -ErrorAction Stop
    } catch {
        Throw "[$((Get-Date).TimeOfDay)] Had trouble with finding the group ""$IncludeACL"". script execution halted!"
    }

    # Get exclude group members
    Write-Output "[$((Get-Date).TimeOfDay)] Collecting computers from OU named ""$ExcludeACL"""
    try {
        $ExcludeGroupMembers = Get-ADGroupMember -Identity $ExcludeACL -ErrorAction Stop
        $GroupMembers += $ExcludeGroupMembers
    } catch {
        Throw "[$((Get-Date).TimeOfDay)] Had trouble finding the group ""$ExcludeACL"". script execution halted!"
    }

    # Removing duplicate entries from object array
    Write-Output "[$((Get-Date).TimeOfDay)] Sorting array for uniques..."
    $GroupMembers = $GroupMembers | sort | Get-Unique
    return $GroupMembers
}

Compare-AppLockerArrays($ref, $diff) {
    # Comparing and finding differences between groups and Organizational unit.
    Write-Output "[$((Get-Date).TimeOfDay)] Comparing arrays for missing objects..."
    $MissingAppLocker = Compare-Object $ref $diff
    return $MissingAppLocker
}

Send-EmailAlert ($MissingAppLocker) {
    Write-Output "[$((Get-Date).TimeOfDay)] The following computer objects are not protected by AppLocker!"

    # Adding missing computers list to email
    $CompCount = 0
    $EmailBody = "<html><body><H1>Computers missing AppLocker assignment</H1><p>These computers are not found in the groups $IncludeACL or $ExcludeACL.</p><ul>"
    foreach ($CompObj in $MissingAppLocker.InputObject) {
        $CompCount++
        $EmailBody += "<li>$($CompObj.DistinguishedName)</li>"
        Write-Output "[$((Get-Date).TimeOfDay)] $($CompObj.DistinguishedName)"
    }

    # Adding excluded computers list to email
    $EmailBody += "</ul><h1>List of excluded computers:</h1><ul>"
    foreach ($CompObj in $ExcludeGroupMembers) {
        $EmailBody += "<li>$($CompObj.DistinguishedName)</li>"
    }

    $EmailBody += "</ul></body></html>"

    $Subject = "$CompCount computers missing AppLocker policies!"

    Write-Output "[$((Get-Date).TimeOfDay)] Sending email to:"
    write-Output "[$((Get-Date).TimeOfDay)] $recipients"

    try{
        Send-MailMessage -BodyAsHtml -From $Emailfrom -To $recipients -Subject $Subject -Body $EmailBody -Priority High -Encoding utf8 -ErrorAction stop
    }catch{
        Write-Output "[$((Get-Date).TimeOfDay)] Error sending email!"
        Write-Error $Error
    }
}

############################################################################################
#
# EXECUTE SECTION
#
############################################################################################

# Start logging to configured directory
Start-Transcript $LogFile -Force

# Look for computer with missing AppLocker policy assignments
$Result = Compare-AppLockerArrays (Build-ReferenceArray) (Build-DifferenceArray)

# Send email alert if missing computers where found
if($Result) {
    Send-EmailAlert $Result
} else {
    Write-Output "[$((Get-Date).TimeOfDay)] It seems that all required computers have an AppLocker policy assigned, Good job!"
}

Write-Output "[$((Get-Date).TimeOfDay)] Execution completed!"

# End logging
Stop-Transcript 
