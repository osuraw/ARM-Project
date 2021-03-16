Install-WindowsFeature -name Web-Server -IncludeManagementTools

$outputFile = "C:\Users\defaultadmin\Downloads\DotnetCoreHostBuddel.exe"
Invoke-WebRequest -Uri https://download.visualstudio.microsoft.com/download/pr/19a5a3cc-b297-4a10-9b22-1184a0aeb990/5af443d748d2c5fb444477f202a11470/dotnet-hosting-3.1.12-win.exe -OutFile $outputFile -UseBasicParsing
Start-Process $outputFile -Wait -ArgumentList '/quiet /install'
net stop was /y
net start w3svc
Remove-Item $outputFile

Remove-WebAppPool -Name 'DefaultAppPool'
Remove-WebSite -Name 'Default Web Site'

$WebPool = "TestApp"
$WebSite = "TestSite"
$WebAppPath = "C:\TestApp"
New-WebAppPool -Name $WebPool
Set-ItemProperty -Path IIS:\AppPools\$WebPool -Name managedRuntimeVersion -Value ""
start-WebAppPool $WebPool

mkdir $WebAppPath

New-WebSite -Name $WebSite -Port 80 -PhysicalPath $WebAppPath
Set-ItemProperty "IIS:\Sites\$($WebSite)" -Name applicationPool -Value $WebPool
Start-Website -Name $WebSite

$outputFile = "C:\Users\defaultadmin\Downloads\webapp.zip"
Invoke-WebRequest -Uri $AppUrl -OutFile $outputFile -UseBasicParsing
Expand-Archive -LiteralPath $outputFile -DestinationPath $WebAppPath
Remove-Item $outputFile