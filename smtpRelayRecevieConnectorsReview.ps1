<#
    .SYNOPSIS
    smtpRelayRecevieConnectorsReview.ps1

    .DESCRIPTION
    This is a revised version of Ali Tajran's script to find IP addresses using Exchange SMTP relay connectors (client connections omitted!).
    The script is intended to help determine servers and senders that are using an Exchange server to connect and send email.
    This is especially pertinent in a decommission scenario, where the logs are to be checked to ensure that
    all SMTP traffic has been moved to the correct endpoint.

    .LINK
    Original Article by Ali: https://alitajran.com/find-ip-addresses-using-exchange-smtp-relay

    .NOTES
    Written by: ALI TAJRAN
    Enhanced by: Michael Mardahl
    Website:    msendpointmgr.com
    Github:     github.com/mardahl
    LinkedIn:   linkedin.com/in/michael-mardahl

    .CHANGELOG
    V1.00, 04/05/2021 - Initial version
    V2.00, 03/28/2023 - Rewrite script to retrieve results faster
    V3.00, 01/18/2024 - Rewrite script to retrieve hostname, senders and recipients
#>

#region declarations

#add all exchange cas netbios hostnames here
$servers = @("cas001","cas002","cas003","cas004")
#Add network or literal paths to servers containing log files (the account running the script must have access!)
$logFilePaths = @("\\hub001\d$\Exchange\TransportRoles\Logs\ProtocolLog\SmtpReceive\*.log","\\hub002\d$\Exchange\TransportRoles\Logs\ProtocolLog\SmtpReceive\*.log")
# Sets the path to the output file that will contain the unique IP addresses
$Output = "C:\temp\smtpReceiveConnectorReview-$(get-date -Format yyyyMMdd-hhmm).txt"

#endregion declarations

# Clears the host console to make it easier to read output
Clear-Host

#connect powershell session to Excahnge

foreach ($server in $servers) {
    if($session){break}
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$server.dt2kmeta.dansketraelast.dk/PowerShell/ -Authentication Kerberos
    $connection = Import-PSSession $Session -DisableNameChecking
}

# Gets a list of the log files in the specified directory
# iterates through logfilepaths to get all child items and add to the $logFiles array
$logFiles = @()
foreach ($logFilePath in $logFilePaths) {
    $logFiles += Get-ChildItem $logFilePath
}

# Gets the total number of log files to be processed
$count = $logFiles.Count

# Initializes an array to store the unique IP addresses
$scanResults = foreach ($log in $logFiles) {

    # Displays progress information
    $percentComplete = [int](($logFiles.IndexOf($log) + 1) / $count * 100)
    $status = "Processing $($log.FullName) - $percentComplete% complete ($($logFiles.IndexOf($log)+1) of $count)"
    Write-Progress -Activity "Collecting Log details" -Status $status -PercentComplete $percentComplete

    # Displays the name of the log file being processed
    Write-Host "Processing Log File $($log.FullName)" -ForegroundColor Magenta

    # Reads the content of the log file, skipping the first five lines
    $fileContent = Get-Content $log | Select-Object -Skip 5

    # Loops through each line in the log file
    foreach ($line in $fileContent) {

        #skip these send connectors:
        if($line -like "*\Default*") {continue}
        if($line -like "*\Client*") {continue}

        # Extracts the IP address from the socket information in the log line
        $socket = $line.Split(',')[5]
        $ip = $socket.Split(':')[0]
        $mail = $line.Split(',')[7]

        if (($mail -ilike "RCPT TO*") -or ($mail -ilike "MAIL FROM*"))
        {
            $senderInfoTemp = $mail.split('>')
            $senderInfo = $senderInfoTemp[0].split(':')
        }
        else {
            #Skip iterations that don't contain a from or to e-mail 
            continue
        }

        # Adds the IP address to the $ips array
        "$($ip);$($senderInfo[0].ToUpper());$($senderInfo[1].ToLower() -replace '<','')" 
    }
}

# Removes duplicate IP addresses from the $ips array and sorts them alphabetically
Write-Progress -Activity "Sorting results" -Status "Processing... (progress bar will not update during)" -PercentComplete 11
$uniques = $scanResults | Sort-Object -Unique 
Write-Progress -Activity "Sorting results" -Status "Completed!" -PercentComplete 100

#set variables for processing
$countTotal = $uniques.count
$count = 1
$resultList = @()
$resultList += "IPaddress;Hostname;Type;MailAddress"
$lastIP = ""
$hostname = ""
foreach ($item in $uniques) {
    $IPaddress = ($item.split(';'))[0]
    $Type = ($item.split(';'))[1]
    $MailAddress = ($item.split(';'))[2]

    #status update
    $percentComplete = [int]($count / $countTotal * 100)
    $status = "Processing $IPaddress - $percentComplete% complete $count of $countTotal)"
    Write-Progress -Activity "Analyzing IPAddress information" -Status $status -PercentComplete $percentComplete

    #get hostname if IP has not been scanned before
    if($IPaddress -eq $lastIP) {
        $hostname = $hostname
    } else {
        $hostname = $false
        $hostsFound = ""
        foreach ($result in $((Resolve-DnsName -Type PTR -Name $IPaddress -ErrorAction SilentlyContinue).Namehost)) {
            $hostsFound = "$result,$hostsFound"
        } 

        if ($hostsFound.Length -lt 2) {
            $hostname = "No PTR found in DNS"
        } else {
            $hostname = $hostsFound.TrimEnd(',')
        }
        $lastIP = $IPaddress
    }
    #output results to array
    $resultList += "$IPaddress;$Hostname;$Type;$MailAddress"
    $count++
}


# Displays the list of unique IP addresses on the console
# $resultList | Out-GridView

# Writes the list of unique IP addresses and senders/recipients to the output file
$resultList | Out-File $Output -Encoding UTF8

Write-Host "Process completed!" -ForegroundColor Green
