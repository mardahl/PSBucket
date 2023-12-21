<#
.SYNOPSIS
This script releases messages from quarantine based on the Internet Message ID exported as a result of Threat Explorer.

.DESCRIPTION
This script connects to Exchange Online and retrieves messages from quarantine using the provided CSV file.
It then releases each message from quarantine and sends it to the recipient. The script outputs the status of each message ID to the console.

.PARAMETER csvFilePath
The path to the CSV file containing the Internet Message IDs. Exported from Microsoft Defender Threat Explorer

.EXAMPLE
Export results from a threat explorer query, and be sure to just export the internet message ID. Then input the file as a parameter of the script.
.\release-ThreatExplorerResults.ps1 -csvFilePath "C:\Users\xxxx\Downloads\All-List_2023-12-11_2023-12-17_UTC.csv"

.NOTES
Author: Michael Mardahl
Version: 1.0
GitHub: https://github.com/mardahl
#>

#Requires -Modules ExchangeOnlineManagement

#Check if the command line param was specified for the CSV location
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

#test CSV file path exit if fails
if (!(Test-Path $csvFilePath)) {
    Write-Host "The CSV file path provided does not exist."
    exit
}

#connecting to exchange online
connect-exchangeonline

# Import the CSV file
$messageIDs = Import-Csv -Path $csvFilePath
$count = $messageIDs.count
$counter = 0
#output the total count of message IDs
Write-Host "Total number of message IDs: $count"
# Loop through each message ID, retrieve the message and release it from quarantine
foreach ($messageID in $messageIDs) {
    try {
        # Retrieve the message from quarantine based on the Internet Message ID
        $quarantineMessage = Get-QuarantineMessage -MessageId $messageID.'Internet Message ID'
        #increment counter and output how many processed out of total count
        $counter++
        Write-Host "Processing message ID: $($messageID.'Internet Message ID') ($counter/$count)"

        # Check if the message exists
        if ($quarantineMessage) {
            # Release the message from quarantine
            $quarantineMessage | Release-QuarantineMessage -ReleaseToAll -WarningAction SilentlyContinue
            Write-Host "Released message: $($messageID.'Internet Message ID')"
        } else {
            Write-Host "No message found with ID: $($messageID.'Internet Message ID')"
        }
    } catch {
        Write-Host "Failed to release message: $($messageID.'Internet Message ID'). Error: $_"
    }
}
#output completion message
Write-Host "Completed releasing all messages"
