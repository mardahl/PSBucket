<#
.SYNOPSIS
    Creates firewall rules for Microsoft Teams.
    Modified substatially from Original version found at: https://docs.microsoft.com/en-us/microsoftteams/get-clients#sample-powershell-script
    by author.
.DESCRIPTION
    (c) Microsoft Corporation 2018 and Michael Mardahl. All rights reserved. Script provided as-is without any warranty of any kind. Use it freely at your own risks.
    Must be run with elevated permissions. 
    Designed to be run as user assigned PowerShell Script from Intune, or as a Scheduled Task run as SYSTEM at user login. 
    The script will create a new inbound firewall rule for the currently logged in user. 
    Requires PowerShell 3.0.
.INPUTS
  None
.OUTPUTS
  Log file stored in %SystemDrive%\Windows\TEMP\log_Update-TeamsFWRules.txt
  Log file is copied to users own TEMP dir IF execution is successful.
.NOTES
  Version:        1.0
  Author:         Michael Mardahl
  Twitter: @michael_mardahl
  Blogging on: www.iphase.dk and www.msendpointmgr.com
  Creation Date:  28 March 2020
  Purpose/Change: Initial script development
.EXAMPLE
  .\Update-TeamsFWRule.ps1 -Force
  Adds the required Teams Firewall Rules
  Execute the script in SYSTEM context!
#>

#Requires -Version 3
#Requires -Runasadministrator

#region Declarations

#Define a log path (defaults to system, but will be copied to the users own temp after successful execution.)
$logPath = join-path -path $($env:SystemRoot) -ChildPath "\TEMP\log_Update-TeamsFWRules.txt"

#Enable forced rule creation, to cleanup any rules the user might have made, and set the standards imposed by this script (suggested setting $True).
$Force = $True

#endregion Declarations

#region Functions

Function Get-LoggedInUserProfile() {
# Tries to figure out who is logged in and returns their user profile path

    try {
    
       $loggedInUser = Gwmi -Class Win32_ComputerSystem | select username -ExpandProperty username
       $username = ($loggedInUser -split "\\")[1]

       #Identifying the correct path to the users profile folder - only selecting the first result in case there is a mess of profiles 
       #(which case you should do a clean up. As this script might not work in that case)
       $userProfile = Get-ChildItem (Join-Path -Path $env:SystemDrive -ChildPath 'Users') | Where-Object Name -Like "$username*" | select -First 1
       
    } catch [Exception] {
    
       $Message = "Unable to find logged in users profile folder. User is not logged on to the primary session: $_"
       Throw $Message
       
    }

    return $userProfile
}

Function Set-TeamsFWRule($ProfileObj) {
# Setting up the inbound firewall rule required for optimal Microsoft Teams screensharing within a LAN.
    
    Write-Verbose "Identified the current user as: $($ProfileObj.Name)" -Verbose
    $progPath = Join-Path -Path $ProfileObj.FullName -ChildPath "AppData\Local\Microsoft\Teams\Current\Teams.exe"

    if ((Test-Path $progPath) -or ($Force)) {

        if ($Force) {
            
            #Force parameter given - attempting to remove any potential pre-existing rules.  
            Write-Verbose "Force switch set: Purging any pre-existing rules." -Verbose  
            Get-NetFirewallApplicationFilter -Program $progPath -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
                
        }
        
        if (-not (Get-NetFirewallApplicationFilter -Program $progPath -ErrorAction SilentlyContinue)) {

            $ruleName = "Teams.exe for user $($ProfileObj.Name)"
            Write-Verbose "Adding Firewall rule: $ruleName" -Verbose
            New-NetFirewallRule -DisplayName "$ruleName" -Direction Inbound -Profile Domain -Program $progPath -Action Allow -Protocol Any
            New-NetFirewallRule -DisplayName "$ruleName" -Direction Inbound -Profile Public,Private -Program $progPath -Action Block -Protocol Any

        } else {
        
            Write-Verbose "Rule already exists!" -Verbose
            
        }

    } else {

       $Message = "Teams not found in $progPath - use the force parameter to override."
       Throw "$Message"

    }
        
}

#endregion Functions

#region Execution

#Start logging
Start-Transcript $logPath -Force

#Add rule to WFAS
Try {
    
    Write-Output "Adding inbound Firewall rule for the currently logged in user."
    #Combining the two function in order to set the Teams Firewall rule for the logged in user
    Set-TeamsFWRule -ProfileObj (Get-LoggedInUserProfile)
    #Copy log file to users own temp directory.
    Copy-Item -Path $logPath -Destination (Join-Path -Path (Get-LoggedInUserProfile).FullName -ChildPath "AppData\Local\Temp\") -Force

} catch [Exception] {
    
    #Something whent wrong and we should tell the log.
    $Message = "Houston we have a problem: $_"
    Write-Output "$Message"
    exit 1

} Finally {

    #Make sure we stop logging no matter what whent down.
    Stop-Transcript

}

#endregion Execution
