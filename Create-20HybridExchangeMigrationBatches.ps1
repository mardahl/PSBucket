<#
    .SYNOPSIS
        Creates about 20 Exchange Online Migration batches containing all the eligeble users in the On-prem Exchange Organization

    .DESCRIPTION
        Can be used by admins to simply create and start about 20 migration batches containing all the user synced
        to Office 365 with the "MailUser" recipient type set.
        UPN's containing onmicrosoft.com will be skipped!
        The script can be run from your local computer as it connects onnly to exchange online.
        If some users are missing, then make sure you have actually synced them from on-prem with AAD Connect.

    .OUTPUTS
        A bunch of CSV files wit the users are left in your temp folder, depending on how you configure the declarations.

    .EXAMPLE
        Run the script without any parameters 
        .\Create-20HybridExchangeMigrationBatches.ps1
        

    .NOTES
        The script must be run interactively.
        This script requires the Exchange Online V2 Powershell module, which it will try to install.
        Modify the declarations region of the script in order to succeed with the execution.
        
        Licensed under MIT, feel free to modify and distribute freely, but leave author credits.
        
        Created by Michael Mardahl
          Twitter: @michael_mardahl
          Github : github.com/mardahl
#>

#region Declarations
$TargetDeliveryDomain = "REPLACE-CAPS-WITH-TENANTNAME.mail.onmicrosoft.com"
$notificationEmail = "myuser@mydomain.com" #will receive batch completion and failure notifications
$badItemLimit = "1000" #Adjust as you see fit
$csvTempPath = join-path "$env:temp" "\CSVTemp"
#endregion Declarations

#region Execute 
Write-Verbose "Connecting to Exchange Online" -Verbose
try {
    #Verify Exchange Online V2 modules are installed
    if(!(Get-InstalledModule ExchangeOnlineManagement)){
        Install-Module ExchangeOnlineManagement -Force
    }
    #Connect to exchange online using modern authentication
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
} catch {
    Throw "Could not connect to exchange online, make sure to get the exchange online v2 module installed"
}
Write-Verbose "Connecting to Exchange Online completed." -Verbose

#Build sorted list of users
Write-Verbose "Building list of users that can be migrated." -Verbose
$batchUsers = Get-User | Where-Object { $_.RecipientType -eq "MailUser" -and $_.Name -notlike "Health*" -and $_.IsDirSynced -eq $true -and $_.UserPrincipalName -notlike "*onmicrosoft.com" } | select UserPrincipalName -ExpandProperty UserPrincipalName | sort UserPrincipalName
Write-Verbose "List creation completed." -Verbose

#Calculate how many users need to be in each batch to fit them all in 20 batches
$batchMembersCount = [math]::floor($batchUsers.Count / 20)

Write-Verbose "Creating temporary CSV files for batch import." -Verbose

#Clear out old CSV files and create temp directory
if (Test-Path $csvTempPath) {  Remove-Item $csvTempPath -Recurse -Force}
$createDir = New-Item -ItemType Directory -Path $csvTempPath

#Create the batch csv files
$upnCount = 0
$fileCount = 1
foreach($upn in $batchUsers){
    
    if($upnCount -eq 0) {
        #Create temporary CSV file on first iteration
        $csvTempFile = Join-Path $csvTempPath "\batch$($fileCount).csv"
        Add-Content -Path $csvTempFile  -Value 'EmailAddress'
    }

    #add users UPN to the initial and subsequent iterations
    Add-Content -Path $csvTempFile  -Value "$upn"
    
    $upnCount++
    if($batchMembersCount -eq $upnCount){
        #reset iteration as we have reached the calculated maximum users of this batch.
        $upnCount = 0
        #Increase filename for next batch iteration.
        $fileCount++
    }
    
}
Write-Verbose "CSV file creation completed." -Verbose

#Create migration batches in Exchange Online

Write-Verbose "Opening migration endpoint select window..." -Verbose
$SourceEndpoint = Get-MigrationEndpoint | Out-GridView -Title "Select 1 migration endpoint for batches..." -PassThru | select Identity -ExpandProperty Identity

Write-Verbose "Adding $fileCount batches to Exchange Online and starting initial sync." -Verbose
$batchCount = 1
Do {
    #Create migration batch for each CSV
    $csvTempFile = Join-Path $csvTempPath "\batch$($batchCount).csv"
    $niceNumber = ([string]$batchCount).PadLeft(2,'0')
    New-MigrationBatch -Name "AutoBatch$($niceNumber)" -SourceEndpoint "$SourceEndpoint" -CSVData ([System.IO.File]::ReadAllBytes("$csvTempFile")) -AutoStart -BadItemLimit $badItemLimit -TargetDeliveryDomain $TargetDeliveryDomain -NotificationEmails $notificationEmail
    $batchCount++
} While ($batchCount -ne $fileCount)

Write-Verbose "Completed batch creation in Exchange Online." -Verbose

Disconnect-ExchangeOnline -Confirm:$false

Write-Verbose "End script." -Verbose
#endregion Execute
