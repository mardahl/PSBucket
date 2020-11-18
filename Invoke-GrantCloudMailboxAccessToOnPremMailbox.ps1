<#
  .DESCRIPTION
    Simple PowerShell script to grant an Exchange Online Mailbox user FullAccess and Send As permission to an On-Prem Mailbox
    
  .NOTES
    Author: @michael_mardahl on Twitter
    Github: github.com/mardahl
    License: MIT
#>

#Exchange on-prem part (must be run on a server with Exchange management tools installed)
$mailbox = Read-Host "Enter UPN of on-prem mailbox you need to grant access TO"
$delegate = Read-Host "Enter UPN of the cloud mailbox that will access the on-prem mailbox"
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn
Add-MailboxPermission –Identity $mailbox –User $delegate –AccessRights FullAccess –AutoMapping $false
Add-MailboxPermission –Identity $mailbox –User $delegate –AccessRights ExtendedRight -ExtendedRights "Send As" –AutoMapping $false

#Exchange Online part (requires EXO Powershell V2 module)
connect-exchangeonline
Add-RecipientPermission $mailbox -AccessRights SendAs -Trustee $delegate
