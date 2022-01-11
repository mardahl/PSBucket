#test outbound network connectivity from Windows Device
#quick and dirty script by Michael Mardahl (github.com/mardahl)
#MIT License

$portArray = @(21,22,25,80,443,587,2525,8080,8443)
foreach ($port in $portArray){
    Write-Host "Testing TCP port: $port `t" -NoNewline
    $result = Test-NetConnection -InformationLevel detailed -ComputerName portquiz.net -Port $port -WarningAction SilentlyContinue
    Write-Host " - Open? :" $result.TcpTestSucceeded
}
