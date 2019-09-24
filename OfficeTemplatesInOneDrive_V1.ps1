#Requires -Version 5.0
<#
.SYNOPSIS
This script will make OneDrive syncronise a Office Templates folder from sharepoint.
.DESCRIPTION
This script will take an ODOPEN protocol URL and add it to the current users OneDrive settings, then add the required registry keys to make Office programs use the new location for templates.
.EXAMPLE
Just run this script without any parameters in the users context (for example, as an Intune Extensions Powershell script)
.NOTES
NAME: OfficeTemplatesInOneDrive_V1.ps1
VERSION: 1a
PREREQ: Create a document library in SharePoint Online, and give the users "Viewer" permissions. (So they can't override templates).
        Create three subfolders named "Word", "Excel" and "PowerPoint" respectively, as registry entries will be made for these folders.
        Get the "ODurl" by pressing the "SYNC" button in the sharepoint site, using the old InternetExplorer, which will show the URL (Other browsers will just sync right away!)
        It's very important that the URL be formattet correctly for use in this script, 
        when replacing it, read the comment before the string line!
.COPYRIGHT
@michael_mardahl / https://www.iphase.dk
Licensed under the MIT license.
Please credit me if you fint this script useful and do some cool things with it.
#>

####################################################
#
# CONFIG SECTION
#
####################################################

# Put your Sharepoint ODOPEN URL here. Remove the &userEmail=xxx@xxxx.xxx part of the string
$ODurl = 'odopen://sync/?scope=OPENLIST&siteId=f534557-942a-4d54-a373-9264641f08583&webId=c0d44985-f744-495a-9339-714d46646f9c&webTitle=Templates&listId=%7B8yyyC68D-YH33-478C-BDB9-88CE1E265488%7D&listTitle=Documents&listTemplateTypeId=101&webUrl=https%3A%2F%2Fcontoso.sharepoint.com%2Fsites%2FTemplates&webLogoUrl=_layouts%2F15%2Fimages%2Fsiteicon.png&webTemplate=7'

# The destination folder that OneDrive creates (you need to manually sync the folder to a test client to determine what this ends up being (no trailing backslash please!)
$SyncPath = "$($env:USERPROFILE)\Contoso Corp\Templates - Documents"

# Set to $false or $true, depending on whether or not you want OneDrive to keep the files available off-line. (I recommend $true)
$pinned = $true

# The version of Office that we are targeting.
$OfficeVersionCode = "16.0" 

####################################################
#
# FUNCTIONS SECTION
#
####################################################

function WaitForOneDrive () {

    <#
    .SYNOPSIS
    This function will check to see if OneDrive is Running on the local machine
    .DESCRIPTION
    The function poll's for the OneDrive process every second, and will resume script execution, once it's running
    .EXAMPLE
    WaitForOneDrive
    .NOTES
    NAME: WaitforOneDrive 
    #>

    $started = $false
    $maxWaitSec = 300 #maximum number of seconds we are willing to wait for the OneDrive Process. (not an exact counter, might be a bit longer)
    $wait = 0 #Initial Wait counter

    Do {

        $status = Get-Process OneDrive -ErrorAction SilentlyContinue #Looking for the OneDrive Process

        If (!($status)) { 
            Write-Output 'Waiting for OneDrive to start...'
            Start-Sleep -Seconds 1 
        } Else { 
            Write-Output 'OneDrive has started yo!'
            $started = $true 
        }

        $wait++ #increase wait counter

        If ($wait -eq $maxWaitSec) {
            Write-Output "Failed to find OneDrive Process. Exiting Script!"
            Exit
        }

    }
    Until ( $started )

}

####################################################
#
# EXECUTE SECTION
#
####################################################
# Now doing what needs to be done...

# Starting our logging to the users TEMP folder.
$logfileName = "OfficeTemplatesInOneDrive_{0}.log" -f $env:USERNAME
Start-Transcript -Path $(Join-Path -Path $env:TEMP -ChildPath $logfileName) -Force
$ODurl = "$ODurl&userEmail=$(whoami /upn)"

# Waiting for OneDrive Process...
WaitForOneDrive

Write-Output "Adding folder to OneDrive for user: $($env:USERNAME) - URL: $ODurl"

# Verifying that the folder does not already exists (If so it's likely they are already syncing it)
# You will need to delete this folder and remove the sync from OneDrive settings, in order to reapply this script!
if (Test-Path -Path $SyncPath -PathType Container) {
    Write-Output "$($env:USERNAME) already has the folder in OneDrive!"
    Stop-Transcript
    exit 0
}

# Telling OneDrive to sync the URL.
try {
    Start-Process $ODurl -ErrorAction Stop
}
catch {
    throw "Failed to launch OneDrive with: $ODurl"
    Stop-Transcript
}

if ($pinned) {
    #Lets just make sure we waited untill OneDrive has some data...
    while ($null -eq (Get-ChildItem -Path $SyncPath)) {
        Start-Sleep -Seconds 30
    }
    New-PSDrive -Name $SyncPath -PSProvider FileSystem -Root $SyncPath -Persist
}

### Setup Templates locations in Word, Excel and Powerpoint
# Also sets the default startup Tab, so templates are shown

# Word
New-ItemProperty "HKCU:\Software\Microsoft\Office\$OfficeVersionCode\Word\Options" -Name "PersonalTemplates" -Value "$SyncPath\Word" -PropertyType ExpandString -Force -Confirm:$false
New-ItemProperty "HKCU:\Software\Microsoft\Office\$OfficeVersionCode\Word\Options" -Name "officestartdefaulttab" -Value "1" -PropertyType DWord -Force -Confirm:$false

# Excel
New-ItemProperty "HKCU:\Software\Microsoft\Office\$OfficeVersionCode\Excel\Options" -Name "PersonalTemplates" -Value "$SyncPath\Excel" -PropertyType ExpandString -Force -Confirm:$false
New-ItemProperty "HKCU:\Software\Microsoft\Office\$OfficeVersionCode\Excel\Options" -Name "officestartdefaulttab" -Value "1" -PropertyType DWord -Force -Confirm:$false

# PowerPoint
New-ItemProperty "HKCU:\Software\Microsoft\Office\$OfficeVersionCode\PowerPoint\Options" -Name "PersonalTemplates" -Value "$SyncPath\PowerPoint" -PropertyType ExpandString -Force -Confirm:$false
New-ItemProperty "HKCU:\Software\Microsoft\Office\$OfficeVersionCode\PowerPoint\Options" -Name "officestartdefaulttab" -Value "1" -PropertyType DWord -Force -Confirm:$false

Stop-Transcript

# Let's tell IME that all is well :)
exit 0
