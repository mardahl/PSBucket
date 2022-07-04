write-host "Removing unwanted built-in apps"

try {
    Get-AppxPackage Microsoft.windowscommunicationsapps | Remove-AppxPackage
    exit 0
} catch {
    write-host "Error removing mail and calendar app"
    exit 1
}