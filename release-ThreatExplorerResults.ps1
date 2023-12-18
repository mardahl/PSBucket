<#
.SYNOPSIS
This script releases messages from quarantine based on the Internet Message ID exported as a result from a Threat Explorer query.

.DESCRIPTION
This script connects to Exchange Online and retrieves messages from quarantine using the provided CSV file.
It then releases each message from quarantine and sends it to the recipient. 
The script outputs the status of each message ID to the console.

.PARAMETER csvFilePath
The path to the CSV file containing the Internet Message IDs. Exported from Microsoft Defender Threat Explorer

.EXAMPLE
.\release-ThreatExplorerResults.ps1 -csvFilePath "C:\Users\xxxx\Downloads\All-List_2023-12-11_2023-12-17_UTC.csv"

.NOTES
Author: Michael Mardahl
Version: 1.0
GitHub: https://github.com/mardahl
#>

#Requires -Modules ExchangeOnlineManagement

#add code for parameter for CSV file, add optioni to hardcode CSV file path as well
param (
    [Parameter(Mandatory = $false)]
    [string]$csvFilePath
)

#Use hardcoded csvFilepath if no parameter was specified
if (!$csvFilePath) {
    $csvFilePath = "C:\Users\xxxx\Downloads\All-List_2023-12-11_2023-12-17_UTC.csv"
    #output that hardcoded value is used because of missing parameter
    Write-Host "No CSV file path was specified. Using hardcoded value: $csvFilePath"
}

#test csv file path exit if fails
if (!(Test-Path $csvFilePath)) {
    Write-Host "The CSV file path provided does not exist."
    exit
}

#connecting to exchange online
connect-exchangeonline

# Import the CSV file
$messageIDs = Import-Csv -Path $csvFilePath

# Loop through each message ID, retrieve the message, and release it from quarantine
foreach ($messageID in $messageIDs) {
    try {
        # Retrieve the message from quarantine based on the Internet Message ID
        $quarantineMessage = Get-QuarantineMessage -MessageId $messageID.'Internet Message ID'

        # Check if the message exists
        if ($quarantineMessage) {
            # Release the message from quarantine
            $quarantineMessage | Release-QuarantineMessage -ReleaseToAll
            Write-Host "Released message: $($messageID.'Internet Message ID')"
        } else {
            Write-Host "No message found with ID: $($messageID.'Internet Message ID')"
        }
    } catch {
        Write-Host "Failed to release message: $($messageID.'Internet Message ID'). Error: $_"
    }
}
