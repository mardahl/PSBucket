# NCSI FIX
# because of: https://directaccess.richardhicks.com/2019/04/17/always-on-vpn-updates-to-improve-connection-reliability/
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator\" -Name "UseGlobalDNS" -PropertyType DWORD -Value 1 -Force

#NRPT FIX
# because of: https://social.technet.microsoft.com/Forums/windowsserver/en-US/a79b1acb-e1b3-4dac-99d6-1cd4ae36920f/nrpt-for-always-on-vpn
New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\Dnscache\Parameters\" -Name "DisableNRPTForAdapterRegistration" -PropertyType DWORD -Value 1 -Force