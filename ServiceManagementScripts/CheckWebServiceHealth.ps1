# $WorkSpace = ''
# Get-WebServicesHealth -WorkSpace $WorkSpace
param (
    [Parameter(Position=0,mandatory=$true)]
    [string] $WorkSpace
)


function Get-WebServicesHealth {
    param (
        $WorkSpace
    )
    
    $ConfigurationFilePath = "$($WorkSpace)\ConfigDetails.json"
    $Configurations = Get-Content $ConfigurationFilePath | ConvertFrom-Json -AsHashtable

    $HostFilePath = $Configurations['HostFilePath']
    $DNSName = $Configurations['DomainName']
    $PrivateKey = $Configurations['SSHPrivateKeyFile']

    $EmailUserName = $Configurations['FromEmailUserName']
    $FromEmailAddress = $Configurations['FromEmailAddress']
    $ToEmailAddress = $Configurations['ToEmailAddress']
    
    $DBServerName = $Configurations['LogDBServerName']
    $LogDBName = $Configurations['LogDBName']
    $LogTableName = $Configurations['LogTableName']
    $DbUserName = $Configurations['LogDBUserName']

    $DbPassword = (Get-AzKeyVaultSecret -VaultName $Configurations['KeyValtName'] -Name $Configurations['VmSecretName']).SecretValue
    $EmailPassword = (Get-AzKeyVaultSecret -VaultName $Configurations['KeyValtName'] -Name $Configurations['EmailSecretName']).SecretValue

    $SiteName = 'Testsite'
    $NumberOfRetries = 5

    $DBDataObject = New-Object -TypeName psobject -Property @{ TimeStamp = Get-Date -Format 'yyyy/MM/dd HH:mm:ss' }
    
    $WebSiteStatus = Get-WebSiteStatusWrapper -DNSName $DNSName -NumberOfRetries $NumberOfRetries
    $DBDataObject | Add-Member -NotePropertyName 'SiteStatus' -NotePropertyValue $WebSiteStatus 
    
    $returndata = Get-WebServiceStatusSSHWrapper -HostFilePath $HostFilePath -SiteName $SiteName -PrivateKey $PrivateKey
        
    $SiteDBLog = @()
    $SiteEmailBody = @{}
    foreach ($SiteStatuDetailes in $returndata) {
        $SiteDBLog += "ComputerName:$($SiteStatuDetailes.ComputerName),Status:$($SiteStatuDetailes.SiteStatus) ||"
        if($SiteStatuDetailes.Status -ne 'Success')
        {
            $SiteEmailBody.Add($SiteStatuDetailes.ComputerName, @{'Site Status' = $SiteStatuDetailes.Status;'Message' = $SiteStatuDetailes.Message})
        }
    }
    
    $DBDataObject | Add-Member -NotePropertyName 'LogRecord' -NotePropertyValue "$SiteDBLog"
    Write-DBLog -DBServerName $DBServerName -LogDBName $LogDBName -LogTableName $LogTableName `
                -DbUserName $DbUserName -DbPassword $DbPassword -DataObject $DBDataObject 
    
    if ($SiteEmailBody.Count -ne 0) {
        $EmailDataObject = New-Object -TypeName psobject -Property @{ TimeStamp = Get-Date -Format 'yyyy/MM/dd HH:mm:ss' }
        $EmailDataObject | Add-Member -NotePropertyName 'ErrorDetails' -NotePropertyValue $SiteEmailBody
        
        Send-Email -FromEmailAddress $FromEmailAddress `
                    -ToEmailAddress $ToEmailAddress `
                    -EmailUserName $EmailUserName `
                    -EmailPassword $EmailPassword `
                    -EmailDataObject $EmailDataObject
    }
}

function Get-WebServiceStatusSSHWrapper {
    param (
        $HostFilePath,
        $SiteName,
        $PrivateKey
    )
    
    $connections =@()
    foreach ($socket in Get-Content $HostFilePath) {
        $connections += "defaultadmin@$($socket)"    
    }
    $Returndata = @()
    $Returndata += Invoke-command -HostName $connections -KeyFilePath $PrivateKey `
                  -ScriptBlock ${Function:Get-WebSiteStatusSSH} `
                  -ArgumentList $SiteName `
                  -ErrorAction SilentlyContinue -ErrorVariable ErrorMessage
  
    if ($ErrorMessage.Count -gt 0) {
        $Returndata += Format-ErrorOutput -ErrorMessage $ErrorMessage 
    }

    return $Returndata
}

function Get-WebSiteStatusSSH {
    param (
        $SiteName 
    )

    Import-Module -UseWindowsPowerShell -Name IISAdministration -WarningAction SilentlyContinue
    
    $TryCount = 0
    $DataObject = New-Object -TypeName psobject -Property @{ ComputerName = $env:computername }

    $IISstatus = (Get-IISSite | Where-Object {$_.Name -eq $SiteName}).state

    $DataObject | Add-Member -NotePropertyName 'SiteStatus' -NotePropertyValue $IISstatus

    if ($null -eq $IISstatus) {
        $DataObject | Add-Member  -NotePropertyMembers @{
            Status = 'Warning'
            Message = 'Site not found'
        }
        return $DataObject
    }
    
    if ($IISstatus -eq "Started") 
    {   
        $DataObject | Add-Member  -NotePropertyMembers @{
            Status = 'Success'
            Message = 'Site In Start State'
        }
        return $DataObject
    }
    else {
        do {            
            Start-IISSite -name $SiteName
            $TryCount+=1            
            $IISstatus = (Get-IISSite | Where-Object {$_.Name -eq $SiteName}).state            
            if ($IISstatus -eq "Started") 
            {   
                break
            }
        } while ($TryCount -lt 3)

        if ($TryCount -ne 3) {
            $DataObject | Add-Member  -NotePropertyMembers @{
                Status = 'Error'
                Message = 'Attempt to start site fails three times'
            }
            return $DataObject
        }
        else{
            $DataObject | Add-Member  -NotePropertyMembers @{
                Status = 'Success'
                Message = 'Site In Start State'
            }
            return $DataObject
        }
    }    
}


function Get-WebSiteStatusWrapper{
    param (
        $DNSName,
        $NumberOfRetries
    )
    $RetryCount = 0
    while ($RetryCount -le $NumberOfRetries) {
        $RetryCount += 1
        $SiteIsUp =  Get-WebSiteStatus -DNSName $DNSName
        if ($SiteIsUp) {
            return 'Site UP'
        }
    }
    return 'Site Down'
}

function Get-WebSiteStatus{
    param (
        $DNSName
    )
    try {
        $response = Invoke-WebRequest -Uri "$($DNSName)/home/HealthProb" -Method Get        
    }
    catch {
        return $False        
    }
    if($response.StatusCode -eq '200'){
        return $True
    }
    return $False
}


function Write-DBLog {
    param (
        [string] $DBServerName,
        [string] $LogDBName,
        [string] $LogTableName,
        [string] $DbUserName,
        [secureString] $DbPassword,
        [psobject] $DataObject
    )

    $Credentials = New-Object System.Management.Automation.PSCredential($DbUserName, $DbPassword)

    Write-SqlTableData -ServerInstance $DBServerName `
                       -SchemaName "dbo" `
                       -DatabaseName $LogDBName `
                       -TableName $LogTableName `
                       -Credential $Credentials `
                       -Timeout 30 `
                       -InputData $DataObject
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

function Format-ErrorOutput {
    param (
        $ErrorMessage
    )

    $Exception = ($ErrorMessage.FullyQualifiedErrorId).split(',')[1]

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
                                        'SiteStatus'   = 'Stoped'
                                        'Status'       = 'Error'
                                        'Message'      = "Exception :: $($Exception)"
                                    } 
        }
    }
    else
    {
        $ErrorObject += New-Object -TypeName psobject -Property @{
                            'ComputerName' = "Computer Name Not Found; One or more Coputers fail to connect"
                            'SiteStatus'   = 'Stoped'
                            'Status'       = 'Error'
                            'Message'      = "Exception :: $($Exception)"
                        }
    }

    return $ErrorObject
}

Get-WebServicesHealth -WorkSpace $WorkSpace