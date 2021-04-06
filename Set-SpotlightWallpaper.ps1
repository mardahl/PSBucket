<#
.SYNOPSIS
    Script that takes the latest Windows Spotlight Lockscreen image and set's it as the current users desktop wallpaper.
.DESCRIPTION
    This script will look in the Spotlight image cache and find the latest image, either Portrait or Landscape, and set is as declared in the script declarations.
.NOTES
    Version       : 1.0b
    Author        : Michael Mardahl
    Twitter       : @michael_mardahl
    GitHub        : github.com/mardahl
    Blogging on   : www.msendpointmgr.com
    Creation Date : 06 April 2021
    Purpose/Change: Initial script development
.EXAMPLE
    execute Set-SpotlightWallpaper.ps1
.NOTES
    Made to be executed as the current user.
#>
#Requires -version 5.0

#region declarations

#Specify wallpaper orientation and style
$orientation = "Landscape" # Landscape or Portrait
$style = "Fill" # Fill, Fit, Stretch, Tile, Center, or Span

#endregion declarations

#region functions

function Test-Image {
    #From Scripting guys blog: https://devblogs.microsoft.com/scripting/psimaging-part-1-test-image/
    [CmdletBinding()]
    [OutputType([System.Boolean])]

    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PSPath')]
        [string] $Path
    )

    PROCESS {

        $knownHeaders = @{
            jpg = @( "FF", "D8" );
            bmp = @( "42", "4D" );
        }

        # coerce relative paths from the pipeline into full paths
        if($_ -ne $null) {
            $Path = $_.FullName
        }

         # read in the first 8 bits
        $bytes = Get-Content -LiteralPath $Path -Encoding Byte -ReadCount 1 -TotalCount 8 -ErrorAction Ignore
        $retval = $false

        foreach($key in $knownHeaders.Keys) {

            # make the file header data the same length and format as the known header
            $fileHeader = $bytes |
                Select-Object -First $knownHeaders[$key].Length |
                ForEach-Object { $_.ToString("X2") }

            if($fileHeader.Length -eq 0) {
                continue
            }

            # compare the two headers
            $diff = Compare-Object -ReferenceObject $knownHeaders[$key] -DifferenceObject $fileHeader
            if(($diff | Measure-Object).Count -eq 0) {
                $retval = $true
            }
        }
        return $retval
    }
}

function Set-WallPaper {
    <#
        .SYNOPSIS
            Applies a specified wallpaper to the current user's desktop
        .PARAMETER Image
            Provide the exact path to the image
        .PARAMETER Style
            Provide wallpaper style (Example: Fill, Fit, Stretch, Tile, Center, or Span)
        .EXAMPLE
            Set-WallPaper -Image "C:\Wallpaper\Default.jpg"
            Set-WallPaper -Image "C:\Wallpaper\Background.jpg" -Style Fit
        .NOTES
            Copied from https://www.joseespitia.com/2017/09/15/set-wallpaper-powershell-function/
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$True)]
        # Provide path to image
        [string]$Image,
        # Provide wallpaper style that you would like applied
        [parameter(Mandatory=$False)]
        [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
        [string]$Style
    )
 
    $WallpaperStyle = Switch ($Style) {
  
        "Fill" {"10"}
        "Fit" {"6"}
        "Stretch" {"2"}
        "Tile" {"0"}
        "Center" {"0"}
        "Span" {"22"}
  
    }

    Write-Verbose "Setting wallpaper in registry and refreshing desktop."
 
    If($Style -eq "Tile") {
 
        $regSet1 = New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
        $regSet2 = New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 1 -Force
 
    }
    Else {
 
        $regSet1 = New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
        $regSet2 = New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 0 -Force
 
    }
 
Add-Type -TypeDefinition @" 
using System; 
using System.Runtime.InteropServices;
  
public class Params
{ 
    [DllImport("User32.dll",CharSet=CharSet.Unicode)] 
    public static extern int SystemParametersInfo (Int32 uAction, 
                                                   Int32 uParam, 
                                                   String lpvParam, 
                                                   Int32 fuWinIni);
}
"@ 
  
    $SPI_SETDESKWALLPAPER = 0x0014
    $UpdateIniFile = 0x01
    $SendChangeEvent = 0x02
  
    $fWinIni = $UpdateIniFile -bor $SendChangeEvent
  
    $ret = [Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Image, $fWinIni)
}

function Get-LatestSpotlightImage {

    <#
        .SYNOPSIS
            Finds the latest lockscreen image from Microsoft Spotlight (needs to be enabled)
        .PARAMETER Orientation
            Please provide the desired orientation of the wallpaper valid options are "Landscape" and "Portrait"
        .EXAMPLE
            Get-LatestSpotlightImage -Orientation "Landscape"
        .NOTES
            Author: Michael Mardahl
            License: MIT - credit author
            GitHub: github.com/mardahl
    #>
    [CmdletBinding()]
    param (
        # Provide the image orientation you want
        [parameter(Mandatory=$True)]
        [ValidateSet('Portrait', 'Landscape')]
        [string]$Orientation
    )

    $SpotlightCachePath = join-path $env:LOCALAPPDATA -ChildPath "\Packages\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\LocalState\Assets"

    if (-not (Test-Path $SpotlightCachePath)){
        Write-Error "Spotlight not enabled for lockscreen, or no images cached in $SpotlightCachePath - terminating script!"
        exit 1
    } else {
    
        #Load image assemblies
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    
        #Get the spotligt image files, newst first
        $latestImages = Get-ChildItem $SpotlightCachePath | Sort LastWriteTime -Descending 

        #Find the latest image in the desired orientation
        foreach ( $image in $latestImages ) {
            #Verify that it is actually an image file!
            $fileName = $image.FullName
            if(-not (Test-Image -Path $fileName)){
                continue
            }
            #Now look for the latest image and return the file path.
            $ImageInfo = [System.Drawing.Image]::FromFile($image.FullName)
            if ($Orientation -eq "Landscape") {
                if ($ImageInfo.Width -eq 1920) {
                    Write-Verbose "Found landscape file: $fileName"
                    break
                }
            } else {
                if ($ImageInfo.Width -eq 1080) {
                    Write-Verbose "Found portrait file: $fileName"
                    break
                }
            }
        }
    }
    return $fileName
}
#endregion functions

#region execute

Write-Host "Spotlight Wallpaper Script executing."
$wallpaper = Get-LatestSpotlightImage -Orientation $orientation -Verbose
Set-WallPaper -Image $wallpaper -Style $style -Verbose

#endregion execute
