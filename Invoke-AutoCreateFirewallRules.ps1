<#
.SYNOPSIS
    Script that evaluates all current network listeners and creates a firewall rule for them.
.DESCRIPTION
    This script will attempt to guess what services you have running on a server that needs to be accessible when activating the windows firewall.
    It is intended to be used on servers that currently have the firewall disabled, and obviously should enable it again without blocking the servers current functions.
.NOTES
    Version       : 1.0b
    Author        : Michael Mardahl
    Twitter       : @michael_mardahl
    GitHub        : github.com/mardahl
    Blogging on   : www.msendpointmgr.com
    Creation Date : 03 Feb 2019
    Purpose/Change: Initial script development
.EXAMPLE
    execute invoke-AutoCreateFirewallRules.ps1
.NOTES
    Made to be executed as the SYSTEM user or an administrator.
    The script does not enable the firewall after the rules have been made, this should be done through GPO to ensure that it is always enabled.
#>

#Requires -Version 4
#Requires -Runasadministrator


#region declarations

        $exclusionNames = "SVCHOST(SSDPSRV)","SVCHOST(iphlpsvc)","SVCHOST(Dnscache)","SVCHOST(CDPSvc)"

#enregion declarations

#region functions

#Netstat'ish function
function Get-NetworkStatistics
{
    $properties = ‘Protocol’,’LocalAddress’,’LocalPort’
    $properties += ‘RemoteAddress’,’RemotePort’,’State’,’ProcessName’,'ProcessPath',’PID’

    netstat -ano | Select-String -Pattern ‘\s+(TCP|UDP)’ | ForEach-Object {

        $item = $_.line.split(” “,[System.StringSplitOptions]::RemoveEmptyEntries)

        if($item[1] -notmatch ‘^\[::’)
        {           
            if (($la = $item[1] -as [ipaddress]).AddressFamily -eq ‘InterNetworkV6’)
            {
               $localAddress = $la.IPAddressToString
               $localPort = $item[1].split(‘\]:’)[-1]
            }
            else
            {
                $localAddress = $item[1].split(‘:’)[0]
                $localPort = $item[1].split(‘:’)[-1]
            } 

            if (($ra = $item[2] -as [ipaddress]).AddressFamily -eq ‘InterNetworkV6’)
            {
               $remoteAddress = $ra.IPAddressToString
               $remotePort = $item[2].split(‘\]:’)[-1]
            }
            else
            {
               $remoteAddress = $item[2].split(‘:’)[0]
               $remotePort = $item[2].split(‘:’)[-1]
            } 

            #Identify shared process names
            $pName = (Get-Process -Id $item[-1] -ErrorAction SilentlyContinue).Name
            if($pName -eq "svchost"){
                $sharedProcName = Get-WmiObject -Class Win32_Service -Filter "ProcessId=$($item[-1])" | select Name -ExpandProperty Name
                $pName = "SVCHOST($sharedProcName)"
            }


            New-Object PSObject -Property @{
                PID = $item[-1]
                ProcessName = "$pName"
                ProcessPath = (Get-Process -Id $item[-1] -ErrorAction SilentlyContinue).Path
                Protocol = $item[0]
                LocalAddress = $localAddress
                LocalPort = $localPort
                RemoteAddress =$remoteAddress
                RemotePort = $remotePort
                State = if($item[0] -eq ‘tcp’) {$item[3]} else {$null}
            } | Select-Object -Property $properties
        }
    }
}

# Firewall rules function
function CreateAllFirewallRules($inputObject){
    if ($null -ne $inputObject) {
        foreach ($listener in $inputObject) {

            $progPort = $listener.LocalPort
            $progPath = $listener.ProcessPath
            $progName = $listener.ProcessName
            $progProtocol = $listener.Protocol

            # Skip exclusion names
            if($exclusionNames -contains $progName) {
                Write-Host "SKIP: $progName excluded." -ForegroundColor Yellow
                continue;
            }


            # setup firewall rules

            # evaluate if we need an application or port exception
            try{
                $testPath = Test-Path $progPath -ErrorAction Stop
                $prog = $true
            }catch{
                $prog = $false
            }

        
            if ($prog -eq $true) {
                # setup firewall for application exception
                # verify the rule does not already exist
                if (-not (Get-NetFirewallApplicationFilter -Program $progPath -ErrorAction SilentlyContinue)) {
                    Write-Host "CREATE : Application rule : $($progName) Allow $($progProtocol)-In" -ForegroundColor Green
                    $ruleName = "AUTO: $($progName) Allow $($progProtocol)-In"
                    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Profile Domain -Program $progPath -Action Allow -Protocol $progProtocol
                    Clear-Variable ruleName

                    Write-Host "CREATE : Application rule : $($progName) Allow $($progProtocol)-Out" -ForegroundColor Green
                    $ruleName = "AUTO: $($progName) Allow $($progProtocol)-Out"
                    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Profile Domain -Program $progPath -Action Allow -Protocol $progProtocol
                    Clear-Variable ruleName
                } else {
                    Write-Host "SKIP: Application rule already exists for : $($progName) Allow $($progProtocol)" -ForegroundColor Yellow
                }
            } else {
                # setup firewall for port exception
                # verify the rule does not already exist

                $testRule = Get-NetFirewallPortFilter -Protocol $progProtocol | Where-Object LocalPort -eq $progPort
                if ($($testrule).count -eq 0) {
                    Write-Host "CREATE : Port rule : $($progName) Allow $($progProtocol)-In ($progPort)" -ForegroundColor Green
                    $ruleName = "AUTO: $($progName) Allow $($progProtocol)-In ($progPort)"
                    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Profile Domain -Program $progPath -Action Allow -Protocol $progProtocol
                    Clear-Variable ruleName

                    Write-Host "CREATE : Port rule : $($progName) Allow $($progProtocol)-Out ($progPort)" -ForegroundColor Green
                    $ruleName = "AUTO: $($progName) Allow $($progProtocol)-Out ($progPort)"
                    New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Profile Domain -Program $progPath -Action Allow -Protocol $progProtocol
                    Clear-Variable ruleName
                } else {
                    Write-Host "SKIP: Port rule already exists for : $($progName) Allow $($progProtocol) ($progPort)" -ForegroundColor Yellow
                }
            }

            Clear-Variable prog
            Clear-Variable progPath
            Clear-Variable progName
            Clear-Variable progProtocol
        }
    }
}

#endregion functions

#region execute

Write-Host "Getting Network listeners for TCP and UDP connections..." -ForegroundColor Green
$discoveredListeners = Get-NetworkStatistics | where-object {($_.State -EQ "LISTENING") -or ($_.Protocol -EQ "UDP")}
clear-host
CreateAllFirewallRules -inputObject $discoveredListeners 

#endregion execute
