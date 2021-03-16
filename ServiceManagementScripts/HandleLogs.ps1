$WorkSpace = ''
Get-WebServiceLogs -WorkSpace $WorkSpace

function Get-WebServiceLogs {
    param (
        $WorkSpace
    )
    
    $ConfigurationFilePath = "$($WorkSpace)\ConfigDetails.json"
    $Configurations = Get-Content $ConfigurationFilePath | ConvertFrom-Json -AsHashtable

    $HostFile = $Configurations['HostFilePath']
    $PrivateKey = $Configurations['SSHPrivateKeyFile']

    $StorageAccountName = $Configurations['StorageAccountName']
    $StorageAccountKey = $Configurations['StorageAccountKey']
    $ContainerName = 'logcontainer'
    
    $EmailUserName = $Configurations['FromEmailUserName']
    $FromEmailAddress = $Configurations['FromEmailAddress']
    $ToEmailAddress = $Configurations['ToEmailAddress']
        
    $EmailPassword = (Get-AzKeyVaultSecret -VaultName $Configurations['KeyValtName'] -Name $Configurations['EmailSecretName']).SecretValue

    $Date = (Get-Date).AddDays(-1).ToString('yy-MM-dd')
    
    $ArchiveLocation = "$($WorkSpace)\$($Date).zip"
    $DownloadLLocation = "$($WorkSpace)\$($Date)"
    mkdir $DownloadLLocation | Out-Null
    
    $ErroDetails = Copy-FilesFromRemoteHosts -HostFile $HostFile -DownloadLLocation $DownloadLLocation -PrivateKey $PrivateKey 
        
    Compress-Archive -Path $DownloadLLocation -CompressionLevel 'Optimal' -DestinationPath $ArchiveLocation
    
    Update-FileArchive -ArchiveLocation $ArchiveLocation -StorageAccountName $StorageAccountName `
                    -StorageAccountKey $StorageAccountKey -ContainerName $ContainerName `
                    -BlobName "$($Date).zip"
    
    if ($ErroDetails.Count -ne 0) {
        Send-Email -EmailUserName $EmailUserName `
                    -EmailPassword $EmailPassword `
                    -FromEmailAddress $FromEmailAddress `
                    -ToEmailAddress $ToEmailAddress `
                    -EmailDataObject $ErroDetails
    }
    
    Remove-Item $DownloadLLocation -Recurse
    Remove-Item $ArchiveLocation
}
       
function Copy-FilesFromRemoteHosts {   
    param (
            $HostFile,
            $DownloadLLocation,
            $PrivateKey
        )
        
    $connections =@()
    foreach ($socket in Get-Content $HostFile) {
        $connections += "defaultadmin@$($socket)"    
    }

    Invoke-command -HostName $connections -KeyFilePath $PrivateKey `
                    -ScriptBlock ${Function:Get-RemoteFiles} `
                    -ErrorAction SilentlyContinue -ErrorVariable ErrorMessage
                    
    for ($i = 0; $i -lt $connections.Count; $i++) {
        $session = New-PSSession -HostName $connections[$i] -KeyFilePath $PrivateKey -ErrorAction SilentlyContinue
        
        if($null -eq $session)    
        {   
            continue
        }

        Copy-Item -Path "C:\Users\defaultadmin\Documents\windows-$($i+1)" -Destination $DownloadLLocation -Recurse -FromSession $session
        
        Remove-PSSession $session
    }

    Invoke-command -HostName $connections -KeyFilePath $PrivateKey `
                    -ScriptBlock {Remove-Item "C:\Users\defaultadmin\Documents\$($env:computername)" -Recurse} `
                    -ErrorAction SilentlyContinue
        
    if ($ErrorMessage.Count -gt 0) {
        return Format-ErrorOutput -ErrorMessage $ErrorMessage
    }
    return @()
}

function Get-RemoteFiles {    
    $LogCollectPath = "C:\Users\defaultadmin\Documents\$($env:computername)"
    mkdir $LogCollectPath | Out-Null

    $Date = (Get-Date).AddDays(-1).ToString('yy-MM-dd')
    $IISLogPath = "C:\inetpub\logs\LogFiles\W3SVC1\u_ex$($Date).log"
    $IISCustomLogPath = "C:\TestApp1\Logs\$($Date).txt"

    if ((Test-Path $IISLogPath -PathType leaf) -eq $true) {
        Copy-Item -Path $IISLogPath  -Destination $LogCollectPath
    }
    if ((Test-Path $IISCustomLogPath -PathType leaf) -eq $true) {
        Copy-Item -Path $IISCustomLogPath  -Destination $LogCollectPath
    }
}

function Update-FileArchive {
    param (
        $ArchiveLocation,
        $StorageAccountName,
        $StorageAccountKey,
        $ContainerName,
        $BlobName
    )
    $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    Set-AzStorageBlobContent -Container $ContainerName -file $ArchiveLocation -blob $BlobName -Context $StorageContext -Force | Out-Null
}

function Format-ErrorOutput {
    param (
        $ErrorMessage
    )

    $RegxMatches = ([regex]'port ([0-9]+)').Matches($ErrorMessage.ErrorDetails.Message)
    
    $ErrorObject = @()
    if ($RegxMatches.Count -gt 0) 
    {
        foreach ($match in $RegxMatches) {
            $port = [int]$match.Groups[1].Value
            $computerID = $port - 220 + 1
            $ErrorObject += New-Object -TypeName psobject `
                            -Property @{
                                        'ComputerName' = "windows-$($computerID)"
                                        'ComputerId'   = $computerID
                                        'Message'      = "Connection establishment failed"
                                    } 
        }
    }
    return $ErrorObject
}

function Send-Email {
    param (
        [string ]$FromEmailAddress,
        [string ]$ToEmailAddress,
        [string ]$EmailUserName,
        [secureString] $EmailPassword,
        [psobject] $EmailDataObject
    )

    $Credentials = New-Object System.Management.Automation.PSCredential($EmailUserName, $EmailPassword)
    Send-MailMessage -From $FromEmailAddress -To $ToEmailAddress -Subject 'Action Required' `
                        -Credential $Credentials -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl `
                        -Body (ConvertTo-Json $EmailDataObject) `
                        -WarningAction SilentlyContinue
}