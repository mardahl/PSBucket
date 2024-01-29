<#
.SYNOPSIS
    Script to set the primary device owner as local administrator and cleanout any other unwanted admins from the local admin group.
.DECRIPTION
    Remediation script for Intune that should be targeted "wide", like all users or all devices.
    When run, it will check membership of an "allow" group. any members of this group that is also the Primary User of the device the script is running on, will then be made "Local Admin".
    If the user is removed from the "Allow" group, then the script will remove them from Local Admins.
    
.NOTES
    Modified from original by Michael Mardahl @APENTO
    GTIHUB: github.com/mardahl
    Original here: https://github.com/damienvanrobaeys/Intune_Add_PrimaryUser_LocalAdmin/blob/main/Add_PrimaryUser_asAdmin_with_Remove.ps1 

    Graph API App Permissions needed (DeviceManagementManagedDevices.Read.All and GroupMember.Read.All and user.readBasic.All)

    USE AS IS! I provide no warranty or guarantees, this is a PoC!
#>

#region declarations

$tenant = "xxxxxxx.onmicrosoft.com" #onmicrosoft.com name
$clientId = "xxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx" #App API premissions on Graph API as Application should be DeviceManagementManagedDevices.Read.All and GroupMember.Read.All and user.readBasic.All
$clientSecret = "xxxxxxxxxxxxxxxxxxxxx"
$Log_File = "$($env:windir)\debug\Add_local_admin.log"
$adminsArray = @("lapsAdmin") #List of admins not to remove besides the built-in admin
$allowedAdminsAADGroupID = "xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" #Object ID of group that lists who is allowed to be local admins on their devices.
$graphApiVersion = "beta"

#endregion declarations

#region functions

Function Write_Log
	{
		param(
		$Message_Type,	
		$Message
		)
		
		$MyDate = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)		
		Add-Content $Log_File  "$MyDate - $Message_Type : $Message"			
		write-host  "$MyDate - $Message_Type : $Message"		
	}

#endregion functions

#region execute
	
If(!(test-path $Log_File)){new-item $Log_File -type file -force}			
$Module_Installed = $False

If(!(Get-Module -listavailable | where {$_.name -like "*Microsoft.Graph.Intune*"})) 
	{
		Install-Module Microsoft.Graph.Intune -ErrorAction SilentlyContinue
		$Module_Installed = $True		
	} 
Else 
	{ 
		Import-Module Microsoft.Graph.Intune -ErrorAction SilentlyContinue
		$Module_Installed = $True				
	}


If($Module_Installed -eq $False) {
    Write_Log -Message_Type "INFO" -Message "Graph Intune module has not been imported"
    exit 1
}


$authority = "https://login.windows.net/$tenant"
Update-MSGraphEnvironment -AppId $clientId -Quiet
Update-MSGraphEnvironment -AuthUrl $authority -Quiet
		
Try
{
	Connect-MSGraph -ClientSecret $ClientSecret -Quiet
	Write_Log -Message_Type "SUCCESS" -Message "Connected to Intune via Graph API"		
}
Catch
{
	Write_Log -Message_Type "ERROR" -Message "Intune Graph API connection failed!"	
  exit 1			
}		
	
$Computer = $env:COMPUTERNAME
$Device_Found = $False
Try
{
    $Get_MyDevice_Infos = Get-IntuneManagedDevice -filter "devicename eq '$Computer'" | Get-MSGraphAllPages
    if($Get_MyDevice_Infos) {
	    Write_Log -Message_Type "INFO" -Message "Device $Computer has been found on Intune as $($Get_MyDevice_Infos.id)"	
	    $Device_Found = $True
    } else {
        throw
    }				
}
Catch
{
    Write_Log -Message_Type "INFO" -Message "Device $Computer has NOT been found on Intune"					
    $Device_Found = $False				
}
				
If($Device_Found -eq $True) {
	$Get_MyDevice_ID = $Get_MyDevice_Infos.id
	Write_Log -Message_Type "INFO" -Message "Device ID is: $Get_MyDevice_ID"				
												
				
	$Resource = "deviceManagement/managedDevices"
	$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)" + "/" + $Get_MyDevice_ID + "/users"
	$Get_Primary_User_ID = ((Invoke-MSGraphRequest -Url $uri -HttpMethod Get).value.id).Trim()
	Write_Log -Message_Type "INFO" -Message "Primary user ID is: $Get_Primary_User_ID"	

  #verify primary user is allowed to be local admin
  $allowedIds = (Get-Groups -groupId $allowedAdminsAADGroupID | Get-Groups_Members).id
	if($allowedIds -contains $Get_Primary_User_ID) {
    Write_Log -Message_Type "INFO" -Message "Primary user ID found in AAD group ID: $allowedAdminsAADGroupID"
    } else {
        Write_Log -Message_Type "ERROR" -Message "Primary user ID NOT found in AAD group ID: $allowedAdminsAADGroupID. Set to remove!"
        $removePrimary = $true
    }
												
	function Convert-ObjectIdToSid
	{
		param([String] $ObjectId)
		$d=[UInt32[]]::new(4);[Buffer]::BlockCopy([Guid]::Parse($ObjectId).ToByteArray(),0,$d,0,16);"S-1-12-1-$d".Replace(' ','-')
	}
						
	$Get_SID = Convert-ObjectIdToSid $Get_Primary_User_ID
	Write_Log -Message_Type "INFO" -Message "Primary user SID is: $Get_SID"				
						
	$Get_Local_AdminGroup = Gwmi win32_group -Filter "Domain='$env:computername' and SID='S-1-5-32-544'"
	$Get_Local_AdminGroup_Name = $Get_Local_AdminGroup.Name
	Write_Log -Message_Type "INFO" -Message "Admin group name is: $Get_Local_AdminGroup_Name"
                
  #Get the built-in Admin name (no matter what the language)
	$Get_Administrator_Name = (Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount = TRUE and SID like 'S-1-5-%-500'").Name					
	$adminsArray += $Get_Administrator_Name.Trim()
  Write_Log -Message_Type "INFO" -Message "Admin user name is: $Get_Local_AdminGroup_Name"
               
  $Local_Admin_Group_Infos = ([ADSI]"WinNT://$env:COMPUTERNAME").psbase.children.find("$Get_Local_AdminGroup_Name")
	$Get_Local_AdminGroup_Members = $Local_Admin_Group_Infos.psbase.invoke("Members")
				
  foreach ($Member in $Get_Local_AdminGroup_Members) {
  $Get_AdminAccount_ADS_Path = $Member.GetType().InvokeMember('Adspath','GetProperty',$null,$Member,$null) 
  $Account_Infos = $Get_AdminAccount_ADS_Path.split('/',[StringSplitOptions]::RemoveEmptyEntries)
  $User_Name = $Account_Infos[-1]
    If (($adminsArray -inotcontains $User_Name) -and ($User_Name -notlike "S-1-12-1-*")) {
      $Local_Admin_Group_Infos.Remove("$Get_AdminAccount_ADS_Path")	
      Write_Log -Message_Type "INFO" -Message "User $User_Name has been removed from the group:  $Get_Local_AdminGroup_Name"									
    } else {
      Write_Log -Message_Type "INFO" -Message "User $User_Name is allowed as permanent member of group:  $Get_Local_AdminGroup_Name"
    }				
  }
  
  #Do nothing more if the primary users is no longer in the group allowed.
	if (-not $removePrimary) {							
		Try	{
			$ADSI = [ADSI]("WinNT://$Computer")
			$Group = $ADSI.Children.Find($Get_Local_AdminGroup_Name, 'group') 
			$Group.Add(("WinNT://$Get_SID"))							
			Write_Log -Message_Type "SUCCESS" -Message "$Get_SID has been added in $Get_Local_AdminGroup_Name"				
		}	Catch {
			Write_Log -Message_Type "ERROR" -Message "$Get_SID has not been added in $Get_Local_AdminGroup_Name"				
		}
  }					
}

#endregion execute
