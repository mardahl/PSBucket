# Script that removes all OneDrives tenant links.
# execute script in the context of the user.
# MIT license @michael_mardahl / github.com/mardahl

try {
    Get-Process onedrive -ErrorAction Stop | Stop-Process -Force
    Write-Host "OneDrive process stopped (OK)"
}
catch { Write-Host "OneDrive not running (OK)" }

try {
    Remove-Item -Path HKCU:\Software\Microsoft\OneDrive\Accounts\* -Recurse -ErrorAction Stop
    Remove-Item -Path HKCU:\software\microsoft\windows\currentversion\explorer\desktop\namespace\* -Recurse -ErrorAction Stop
    Write-Host "Unliked OneDrive from all tenants (OK)"
} catch { Write-Host "Unlinking of OneDrive from all tenants had errors. Verify the profile is gone for user $(whoami /upn) (WARNING)" }
