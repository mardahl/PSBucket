<#
.SYNOPSIS
    Script to DETECT if we need to set the primary device owner as local administrator and cleanout any other unwanted admins from the local admin group.

.NOTES
    Modified from original by Michael Mardahl @APENTO
    Original here: https://github.com/damienvanrobaeys/Intune_Add_PrimaryUser_LocalAdmin/blob/main/Add_PrimaryUser_asAdmin_with_Remove.ps1 
#>

#region declarations

$tenant = "starkworkspace.onmicrosoft.com" #onmicrosoft.com name
$clientId = "b82db6f3-14b5-4402-b588-5bf0f7a67ed6" #App API premissions on Graph API as Application should be DeviceManagementManagedDevices.Read.All and GroupMember.Read.All and user.readBasic.All
$clientSecret = "xiM8Q~TzeZ4ew-iPjWXHrVFV1RMa5hw1QioEDckY"
$Log_File = "$($env:windir)\debug\Add_local_admin.log"
$adminsArray = @("starkls") #List of admins not to remove besides the built-in admin
$allowedAdminsAADGroupID = "0ca42b5b-f388-40df-be7c-b2afadd88ee1" #Object ID of group that lists who is allowed to be loal admins on their devices.
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
	$Intune_Connected = $True		
}
Catch
{
	Write_Log -Message_Type "ERROR" -Message "Intune Graph API connection failed!"	
    exit 1			
}		
		
If($Intune_Connected -eq $True)
	{	

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
				
		If($Device_Found -eq $True)	{
			$Get_MyDevice_ID = $Get_MyDevice_Infos.id
			Write_Log -Message_Type "INFO" -Message "Device ID is: $Get_MyDevice_ID"				
												
				
			$Resource = "deviceManagement/managedDevices"
			$uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)" + "/" + $Get_MyDevice_ID + "/users"
			$Get_Primary_User_ID = ((Invoke-MSGraphRequest -Url $uri -HttpMethod Get).value.id).Trim()
			Write_Log -Message_Type "INFO" -Message "Primary user ID is: $Get_Primary_User_ID"	

            #verify primary user is allowed to be local admin
            $allowedIds = (Get-Groups -groupId $allowedAdminsAADGroupID | Get-Groups_Members).id
			if($allowedIds -contains $Get_Primary_User_ID) {
                Write_Log -Message_Type "INFO" -Message "Primary user ID found in Entra group ID: $allowedAdminsAADGroupID"
                $removePrimary = $False
            } else {
                Write_Log -Message_Type "ERROR" -Message "Primary user ID NOT found in Entra group ID: $allowedAdminsAADGroupID. Set to remove!"
                $removePrimary = $True
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
            Write_Log -Message_Type "INFO" -Message "Admin user name is: $Get_Administrator_Name"
               
            $Local_Admin_Group_Infos = ([ADSI]"WinNT://$env:COMPUTERNAME").psbase.children.find("$Get_Local_AdminGroup_Name")
			$Get_Local_AdminGroup_Members = $Local_Admin_Group_Infos.psbase.invoke("Members")
				
            #Determine if Primary user is already in Local Admins Group
            $Get_Primary_User_Name = "unknown"
            $localSIDs = (Get-childItem ‘HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList’ | % {Get-ItemProperty $_.pspath }) | select ProfileImagePath, PSChildName
            foreach($item in $localSIDs){
                #Getting the uasername from SID va registry
                if(($item.PSChildName).trim() -eq $Get_SID) {
                    $Get_Primary_User_Name = $item.ProfileImagePath.Split('\')[-1]
                }
            }

            foreach ($Member in $Get_Local_AdminGroup_Members) {
				$Get_AdminAccount_ADS_Path = $Member.GetType().InvokeMember('Adspath','GetProperty',$null,$Member,$null) 
				$Account_Infos = $Get_AdminAccount_ADS_Path.split('/',[StringSplitOptions]::RemoveEmptyEntries)
				$User_Name = $Account_Infos[-1]

                #DETERMINE REMEDIATION

                #User is found in local admins and should not be removed
                if(($User_Name -eq $Get_Primary_User_Name) -and ($removePrimary -eq $False)) {
                    Write_Log -Message_Type "INFO" -Message "User $Get_Primary_User_Name found and should not be removed"
                    Write-Output "found - dont remediate"
                    exit 0
                }
                #User is found in local admins and should be removed
                if(($User_Name -eq $Get_Primary_User_Name) -and ($removePrimary -eq $True)) {
                    Write_Log -Message_Type "INFO" -Message "User $Get_Primary_User_Name found and should be removed because they are no longer in the group."
                    Write-Output "found - remediate"
                    exit 1
                }
			}

            #User is NOT found in local admins and should NOT be removed
            if($removePrimary -eq $False) {
                Write_Log -Message_Type "INFO" -Message "User $Get_Primary_User_Name ($Get_Primary_User_ID) not found and should not be removed"
                Write-Output "not found - remediate"
                exit 1
            }
            #User is NOT found in local admins and should be removed
            if($removePrimary -eq $True) {
                Write_Log -Message_Type "INFO" -Message "User $Get_Primary_User_Name ($Get_Primary_User_ID) not found and should not even be there, so let's just quit!"
                Write-Output "not found - dont remediate"
                exit 0
            }
                    				
		}
	}

#endregion execute
