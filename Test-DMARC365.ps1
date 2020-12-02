<#
.SYNOPSIS
    Check domains for DMARC readiness with Exchange Online

.DESCRIPTION
    This script will verify the presence of the required records for using DMARC with a domain in Exchange Online.
    It's a very simple check to let you know if anything was missed on one or more domains.
    The output is sent to a GridView where it is easy to copy to a spreadsheet for further work.

.INPUTS
    None

.NOTES
    Version       : 1.0b
    Author        : Michael Mardahl
    Twitter       : @michael_mardahl
    Blogging on   : www.msendpointmgr.com
    Creation Date : 02 December 2020
    Purpose/Change: Initial script development
    License       : MIT (Leave author credits)

.EXAMPLE
    Execute script after modification.
    .\Test-DMARC365.ps1
    (Needs to be executed interactively)

.NOTES
    You ned to edit the array of domains in the "declarations" region of the script.
    If you are not familiar with arrays, please notice and keep the formatting.
    For more advanced cases, you can modify to use a CSV file.

#>

#region declarations

$domainArray = @("apento.com","msendpointmgr.com","iphase.dk","microsoft.com")

#endregion declarations

#region functions

#Custom function to generate object with domain specific data about DKIM, DMARC, SPF and MX
function getDomainInfo {
    [cmdletbinding()]
    param (

        [Parameter(Mandatory = $true)]
        [String]$FQDN

    )
    #Hide errors
    $prevErrPref = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"

    #Set values to not found
    $resultMX = "N/A";$resultDMARC = "N/A"; $resultDKIM = "N/A"; $resultSPF = "N/A"

    #Testing MX, SPF, DMARC and DKIM
    if(Resolve-DnsName $FQDN -Type MX | select NameExchange -First 1 -ExpandProperty NameExchange){

        $resultMX = "Present"

    }

    if(Resolve-DnsName $FQDN -Type TXT | Where-Object Strings -ILike "v=spf1*"){

        $resultSPF ="Present"

    }

    if(Resolve-DnsName "_dmarc.$FQDN" -Type TXT | Where-Object Strings -ILike "v=DMARC1*"){

        $resultDMARC = "Present"

    }

    if((Resolve-DnsName "selector1._domainkey.$FQDN" -Type CNAME) -or (Resolve-DnsName "selector2._domainkey.$FQDN" -Type CNAME)){

        $resultDKIM = "Present"

    }

    $statusObject = [PSCustomObject]@{

        DomainName          = $FQDN
        DMARC               = $resultDMARC
        MX                  = $resultMX
        SPF                 = $resultSPF
        DKIM                = $resultDKIM

    }

    #Reset error messages and return object
    $ErrorActionPreference = $prevErrPref
    Return $statusObject
}

#endregion functions

#region execute

#Array with all the domains data
[System.Collections.ArrayList]$statusArray = @()

#Iterate throguh the domains with the custom function
foreach($dom in $domainArray){

    $statusArray.Add((getDomainInfo -FQDN $dom)) | Out-Null

}

#Output to gridview (can be copied directly to spreadsheet
$statusArray | Out-GridView -Title "DMARC test result" -OutputMode Multiple

#endregion execute
