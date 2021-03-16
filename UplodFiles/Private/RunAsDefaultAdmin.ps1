param (
    $PublicKey,
    $PowerShellProfileUrl
)

#download SSH public key
mkdir "C:\Users\defaultadmin\.ssh"
Invoke-WebRequest -Uri $PublicKey -OutFile "C:\Users\defaultadmin\.ssh\authorized_keys" -UseBasicParsing


$DownloadLocation = 'C:\Users\defaultadmin\Downloads\'

#Download Notepad++; for debugging
Invoke-WebRequest -Uri 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v7.9.3/npp.7.9.3.portable.zip' -OutFile "$($DownloadLocation)notepad.zip"
Expand-Archive -LiteralPath "$($DownloadLocation)notepad.zip" -DestinationPath "$($DownloadLocation)notepad++"

#Download Powershell; for SSH Remorting
$url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.1.2/PowerShell-7.1.2-win-x64.msi'
Invoke-WebRequest -Uri $url -OutFile "$($DownloadLocation)powershell.msi" -UseBasicParsing
Start-Process msiexec.exe -Wait -ArgumentList "/package $($DownloadLocation)powershell.msi  /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1"


$PowerShellProfilePath = 'C:\Program Files\PowerShell\7'
Invoke-WebRequest -Uri $PowerShellProfileUrl -OutFile "$($PowerShellProfilePath)\Profile.ps1" -UseBasicParsing
