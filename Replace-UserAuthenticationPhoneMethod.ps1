<# 
  .SYNOPSIS
    Script to replace authentication details for basic mobile MFA.
    
  .DESCRIPTION
    This script will connect to the Microsoft Graph using the official PowerShell SDK and set/replace a specific users Mobile authentication details for MFA.
    This is just some example code for PoC.
    
  .NOTES
    Using Device Code login might not work with PowerShell ISE, so please execute from regular PS session.
    Requires that the user authenticating the device code login has Authentication Administrator rights in AAD.
    At the time of writing this, non-interactive login does not support replacing the authentication phone method.
    
    Autor: Michael Mardahl / github.com/Mardahl / @michael_mardahl
    License: MIT standard license applies, please credit me if you learned something from this.
    
  .EXAMPLE
    Install the Microsoft.Graph module and execute script without parameters after updating the "declarations" region of the script.
    https://github.com/microsoftgraph/msgraph-sdk-powershell/blob/dev/samples/0-InstallModule.ps1

#>
#requires -module microsoft.graph
#requires -Version 6

#region declarations

$targetUser = "myUser@myDomain.com"
$targetUSerMobile = "+00 00000000" #Must be in this format, rememebr the space between country code and phone
$graphApiVersion = 'beta' #Required MSGraphSettings as long as authentication is still in beta for the Graph API.
$ErrorActionPreference = 'Stop'

#endregion declarations

#region execute

#Connect to the desired graph endpoint (SLOW!)
Select-MgProfile -Name $graphApiVersion

#Connect to the Microsoft Graph using Device code interactive flow
Connect-Graph -Scopes "User.Read.All", "UserAuthenticationMethod.ReadWrite.All"

#Obtain user object from graph
$user = get-mguser -UserId $targetUser
$currentSettings = Get-MgUserAuthenticationPhoneMethod -UserId $user.Id

#Check for any current phone and replace it.
if ($currentSettings.PhoneNumber) {
    Remove-MgUserAuthenticationPhoneMethod -UserId $user.Id -PhoneAuthenticationMethodId $currentSettings.Id
}
New-MgUserAuthenticationPhoneMethod -UserId $user.Id -PhoneNumber $targetUSerMobile -PhoneType "mobile"

Disconnect-Graph #closing graph session
#endregion execute
