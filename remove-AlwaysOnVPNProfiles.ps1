<# 
  .SYNOPSIS
    Script to remove unwanted Always On VPN user profiles from client
    
  .DESCRIPTION
    This script will remove both a specified case sensitive user VPN profile and/or a wildcard search for a name of another set of profiles that you want removed.
    
  .NOTES
    I take no responsability for the functionality of this script, use at own risk.
    Autor: Michael Mardahl / github.com/Mardahl / @michael_mardahl
    License: MIT standard license applies, please credit me if you learned something from this.
    
  .EXAMPLE
    Adjust the script delcarations to suit your needs and run remove-AlwaysonVPNProfile.ps1 as a PowerSehll Scritp throught Intune, ConfigMgr or GPO.
    The script must run in SYSTEM context.
#>

#region declarations
#Connection to be removed
$ProfileName = 'myCorp AlwaysOn VPN'
$ProfileNameEscaped = $ProfileName -replace ' ', '%20'

#Remove old connections fix
$removeNameLike = "mycorp*" #not case sensitive and can contain wildcards *
#endregion declarations

#region execute
#Preparing WMI Vars
$nodeCSPURI = './Vendor/MSFT/VPNv2'
$namespaceName = 'root\cimv2\mdm\dmmap'
$className = 'MDM_VPNv2_01'

try
{
    $username = Gwmi -Class Win32_ComputerSystem | select username
    $objuser = New-Object System.Security.Principal.NTAccount($username.username)
    $sid = $objuser.Translate([System.Security.Principal.SecurityIdentifier])
    $SidValue = $sid.Value
    $Message = "User SID is $SidValue."
    Write-Host "$Message"
}
catch [Exception]
{
    $Message = "Unable to get user SID. User may be logged on though Remote Desktop: $_"
    Write-Host "$Message"
    exit
}

$session = New-CimSession
$options = New-Object Microsoft.Management.Infrastructure.Options.CimOperationOptions
$options.SetCustomOption('PolicyPlatformContext_PrincipalContext_Type', 'PolicyPlatform_UserContext', $false)
$options.SetCustomOption('PolicyPlatformContext_PrincipalContext_Id', "$SidValue", $false)

try
{
    $deleteInstances = $session.EnumerateInstances($namespaceName, $className, $options)
    foreach ($deleteInstance in $deleteInstances)
    {
        $InstanceId = $deleteInstance.InstanceID
        if ("$InstanceId" -eq "$ProfileNameEscaped")
        {
            $session.DeleteInstance($namespaceName, $deleteInstance, $options)
            $Message = "Removed existing $ProfileName profile named: $InstanceId"
            Write-Host "$Message"
        } elseif ("$InstanceId" -iLike $removeNameLike)
        {
            $session.DeleteInstance($namespaceName, $deleteInstance, $options)
            $Message = "Removed wildcard matched ($removeNameLike) profile named: $InstanceId"
            Write-Host "$Message"
        } else {
            $Message = "Ignoring existing VPN profile $InstanceId"
            Write-Host "$Message"
        }
        Write-Host $Message
    }
}
catch [Exception]
{
    $Message = "Unable to remove existing outdated instance(s) of $ProfileName profile: $_"
    Write-Host "$Message"
    exit
}

$Message = "User tunnel uninstall completed."

Write-host $Message
#endregion execute
