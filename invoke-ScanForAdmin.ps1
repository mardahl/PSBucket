<#
.SYNOPSIS
    Find hostnames of devices that are using a specific account for authentication
    This script is designed to be run on each Domain Controller in order to snuff out the use of teh built-in Administrator account.
.INPUTS
    None
.NOTES
    Version       : 1.0
    Author        : Michael Mardahl
    Twitter       : @michael_mardahl
    Blogging on   : www.msendpointmgr.com
    Creation Date : 9th Feburary 2022
    Purpose/Change: Initial script
    License       : MIT (Leave author credits)
.EXAMPLE
    Execute script as system or administrator
    .\invoke-ScanForAdmin.ps1
.NOTES
    Some blanks might appear if there is no IP or DNS resolution.
#>

#region declarations

$username = "Administrator" #replace with the username you are scanning the security log for
$outputCSV = ".\results.csv" #path and filename to export csv to

#endregion declarations

#region execute
$events = Get-WinEvent -FilterHashtable @{logname='security';} | where-object  { $_.Id -eq '4624' } | where-object  { $_.Message -like "*$username*" }

#scanning eventlog results for IPadressess and counting results per IP.
$ipadresses = @{}
foreach ($event in $events) {
    if ($event.message -like "*Source Network Address:*") {
        $message = $event.message -split "`r`n"
        foreach ($line in $message) {
            if($line -like "*Source Network Address:*") {
                $hostip = ""
                $hostip = ($line -split ":")[1].TrimStart()
                if($ipadresses[$hostip]) {
                    $ipadresses[$hostip] = $ipadresses[$hostip] + 1
                    break
                }
                Write-verbose $hostip -verbose
                $ipadresses.add( $hostip, 1 )
                break
            }
        }
    }
}

#Building list of hostnames via DNS results and putting into an array of custom objects
$hosts = @()
foreach ($ip in $ipadresses.Keys) {

    $hostname = $([string](Resolve-DnsName $ip -ErrorAction SilentlyContinue).NameHost)
    
    $hosts += [PSCustomObject]@{
        ip     = $ip
        hostname = "$hostname"
        count    = $ipadresses[$ip]
    }

}

$hosts | Export-Csv $outputCSV -Force
$hosts
#endregion execute
 
