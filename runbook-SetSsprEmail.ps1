<#
.SYNOPSIS
  This script will add a users personal e-mail account to their corporate account as a self service password reset (SSPR) option.

.DESCRIPTION
  This script will set the SSPR e-mail address for a list of users in a CSV formatted string.
  The CSV should have a header row with the following columns: upn,ssprMail
  The upn column should contain the user's UPN from Entra ID (Azure AD).
  The ssprMail column should contain the e-mail address to be used for SSPR (typically a personal e-mail address).
  The script will check if the user already has an SSPR e-mail address set, and if so will skip that user.
  The script will output a list of users that failed to have their SSPR e-mail address set.

.EXAMPLE
  Create a new runbook in Azure automation and fill out the required data in the $csvString variable and execute the runbook.

.NOTES
  required permissions: UserAuthenticationMethod.ReadWrite.All must be set on the system-managed identity of the automation account

.AUTHOR
  Michael Mardahl
  github.com/mardahl

.DATE
  July 19, 2023

.VERSION
  1.0.0
#>
#Requires -module microsoft.graph.authentication, microsoft.graph.identity.signins

#conneting to graph with managed identity
connect-graph -identity

#building csv string (insert required data with comma separator)
$csvString = @"
upn,ssprMail
john.smith@contoso.com,thejohnsmith@gmail.com
irfan.hammim@contoso.com,irfan@example.com
sloan.jensen@contoso.com,sloan58@yahoo.com
mbuktu.kawali@contoso.com,kawalim97@outlook.com
"@

#convert csv string to array and setting up otehr needed arrays
$ssprArray = ConvertFrom-Csv -Delimiter "," -InputObject $csvString
$failArray = @()
$errorsArray = @()

#loop through each user in the array and set their SSPR e-mail address
foreach ($user in $ssprArray) {
    write-output "[INFO] Setting SSPR for $($user.upn) to be $($user.ssprMail)"

    #define json body for SSPR e-mail address
    $params = @{
        emailAddress = $user.ssprMail
    }

    #testing if user already has an SSPR e-mail address set, if so skip this user
    try {
        $testForExisting = Get-MgUserAuthenticationEmailMethod -UserId $user.upn -erroraction stop
        if ($testForExisting) {
            write-output " - $($user.upn) already has an SSPR e-mail set - skipping"
            continue
        }
    } catch {
    }  

    #attempting to add the SSPR e-mail address
    try {
        $addEmail = New-MgUserAuthenticationEmailMethod -UserId $user.upn -BodyParameter $params -erroraction stop
    } catch {
        $errorsArray += $addEmail
        $failArray += $user
    }  
}

#output results
if ($failArray) {
  Write-Output "[WARNING] Setting SSRP completed for all users except the following:"
  $failArray | Format-Table
} else {
  Write-Output "[INFO] Setting SSRP completed for all users."
}

#end script with disconnecting from graph
disconnect-graph
