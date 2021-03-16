param (
    $SSHDUrl
)


Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

Invoke-WebRequest -Uri $SSHDUrl -OutFile "C:\ProgramData\ssh\sshd_config" -UseBasicParsing
Restart-Service sshd

