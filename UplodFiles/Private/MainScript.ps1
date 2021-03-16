param (
    $Password,
    $SshdURL,
    $PublicKeyUrl,
    $PowerShellProfileUrl,
    $AppUrl
)

$SecurePassword =  ConvertTo-SecureString -String $Password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\defaultadmin", $SecurePassword)
$command = $PSScriptRoot + "\RunAsDefaultAdmin.ps1"

Enable-PSRemoting -force
Invoke-Command -FilePath $command -Credential $credential -ComputerName $env:COMPUTERNAME -ArgumentList $PublicKeyUrl,$PowerShellProfileUrl
Disable-PSRemoting -Force

Set-Location $PSScriptRoot

.\ConfigureSSH.ps1 -SSHDUrl $SshdURL

.\ConfigureWebService.ps1 -AppUrl $AppUrl