# $WorkSpace = ''
# $ExtractFolderLocation = ''
# $ResourceGroupName = ''
# $ResourceGroupLocation = ''
# $KeyValtName = ''
# $VmSecretName = ''
# $EmailSecretName = ''

# Set-Environment -WorkSpace $WorkSpace `
#                     -ExtractFolderLocation $ExtractFolderLocation `
#                     -ResourceGroupName $ResourceGroupName `
#                     -ResourceGroupLocation $ResourceGroupLocation `
#                     -KeyValtName $KeyValtName `
#                     -VmSecretName $VmSecretName `
#                     -EmailSecretName $EmailSecretName

param (
    $WorkSpace,
    $ExtractFolderLocation,
    $ResourceGroupName,
    $ResourceGroupLocation,
    $KeyValtName,
    $VmSecretName,
    $EmailSecretName
)

function Set-Environment {
    param (
        [Parameter(mandatory=$true)]
        [string]$WorkSpace,
        [Parameter(mandatory=$true)]
        [string]$ExtractFolderLocation,
        [Parameter(mandatory=$true)]
        [string]$ResourceGroupName,
        [Parameter(mandatory=$true)]
        [string]$ResourceGroupLocation,
        [string]$KeyValtName,
        [string]$VmSecretName,
        [string]$EmailSecretName
    )

    if ((Test-Path $WorkSpace) -ne $true) {
        Write-Host "Path '$($WorkSpace)' Does Not Exist"
        break
    }

    if ((Test-Path "$($ExtractFolderLocation)\DeployResources.ps1" -PathType leaf) -ne $true) {
        Write-Host "Extracted File Not found in Path '$($ExtractFolderLocation)'."
        break
    }
    
    if((Get-ResourceGroupAvalability $ResourceGroupName)){
       $status = New-AzResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -ErrorAction SilentlyContinue
       if($null -eq $status)
       {
           Write-Host "Pleas Check Location Parameter"
           break
       }
    }
    else {
        Write-Host 'Resource Group Allready Exist'
        break        
    }
    
    $ConfigurationFolderPath = "$($WorkSpace)\$($ResourceGroupName)-$($ResourceGroupLocation)"
    if ((Test-Path $ConfigurationFolderPath) -eq $true) {
        Write-Host "Similar deployment already exist; Clear folder at >> $($ConfigurationFolderPath)"
        break
    }
    mkdir $ConfigurationFolderPath | Out-Null
    Write-Host "Folder to store configurations created at >> $($ConfigurationFolderPath)"
    
    #Generate SSH Key-pare and move public key to uploadfiles>public
    
    $SSHPrivateKeyFile = "$($ConfigurationFolderPath)\id_rsa"
    ssh-keygen -f $SSHPrivateKeyFile -q -N """"

    $ResourcePrefix = ("$($ResourceGroupName)$($ResourceGroupLocation)").subString(0,16)

    #Store Configurations
    $Configurations = @{
        ExtractFolderLocation = $ExtractFolderLocation;
        ConfigurationFolderPath = $ConfigurationFolderPath;
        ResosurceGroup = $ResourceGroupName;
        ResourceGroupLocation = $ResourceGroupLocation;
        ResourcePrefix = $ResourcePrefix
        SSHPrivateKeyFile = $SSHPrivateKeyFile;
        KeyValtName = $KeyValtName;
        VmSecretName = $VmSecretName;
        EmailSecretName = $EmailSecretName;
    }
    $Configurations | ConvertTo-Json  | Out-File -FilePath "$($ConfigurationFolderPath)\ConfigDetails.json"

    Deploy-SupportResources -ConfigurationFolderPath $ConfigurationFolderPath
    
    Deploy-WebService  -ConfigurationFolderPath $ConfigurationFolderPath 

    Add-Parameters -ConfigurationFolderPath $ConfigurationFolderPath

    Remove-StorageContainer -ConfigurationFolderPath $ConfigurationFolderPath

    $Configurations = Get-Content "$($ConfigurationFolderPath)\ConfigDetails.json" | ConvertFrom-Json -AsHashtable

    Write-Host "Web-Site hosted at >> $($Configurations['DomainName'])"
}

function Get-ResourceGroupAvalability {
    param (
        $ResourceGroupName
    )
    $Response = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

    return $null -eq $Response
}

function Deploy-SupportResources {
    param (
        $ConfigurationFolderPath
    )
    
    $Configurations = Get-Content "$($ConfigurationFolderPath)\ConfigDetails.json" | ConvertFrom-Json -AsHashtable

    $ResourceGroupName = $Configurations['ResosurceGroup']
    $ExtractFolderLocation = $Configurations['ExtractFolderLocation']
    $Password = (Get-AzKeyVaultSecret -VaultName $Configurations['KeyValtName'] -Name $Configurations['VmSecretName']).SecretValue

    $DeploymentOutput = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
            -Name ($ResourceGroupName+"_ENV_"+(Get-Date -Format "dd-MM-yy_HH-mm")) `
            -TemplateFile "$($ExtractFolderLocation)\DeploymentTemplates\EnvironmentSetup.json" `
            -TemplateParameterFile "$($ExtractFolderLocation)\DeploymentTemplates\EnvironmentSetup.parameters.json" `
            -ResourcePrefix $Configurations['ResourcePrefix'] `
            -AdminPassword $Password
                
    $OutputValues = $DeploymentOutput.Outputs
    $StorageAccountName = $OutputValues['storageAccountName'].value
    $LogDBServerName = $OutputValues['dbServerName'].value
    $LogDBName = $OutputValues['dbName'].value
    $LogDBUserName = $OutputValues['dbUserName'].value
    
    #upload files
    
    $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName)[0].Value
    $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

    Set-AzStorageBlobContent -File "$($ConfigurationFolderPath)\id_rsa.pub" -Container 'public'  -Context $StorageContext -InformationAction SilentlyContinue -Force | Out-Null
    Get-ChildItem "$($ExtractFolderLocation)\UplodFiles\Public" | Set-AzStorageBlobContent -Container 'public'  -Context $StorageContext -InformationAction SilentlyContinue -Force | Out-Null
    Get-ChildItem "$($ExtractFolderLocation)\UplodFiles\Private" | Set-AzStorageBlobContent -Container 'private'  -Context $StorageContext -InformationAction SilentlyContinue -Force | Out-Null
    
    $StorageAccountSASKey = New-AzStorageContainerSASToken -Context $StorageContext -Name 'private' -Permission 'r' -ExpiryTime (Get-Date).AddHours(1)
    # ======================================
    
    # Create Db table to store log details
    $Credentials = New-Object System.Management.Automation.PSCredential($LogDBUserName, $Password)
    Invoke-Sqlcmd -InputFile "$($ExtractFolderLocation)\DeploymentTemplates\CreateTable.sql" `
                    -Credential $Credentials `
                    -ServerInstance $LogDBServerName `
                    -Database $LogDBName 
    # ====================================

    # Update Configurations
    $Configurations += @{
        StorageAccountName = $StorageAccountName;
        StorageAccountKey = $StorageAccountKey;
        StorageAccountSASKey = $StorageAccountSASKey;
        LogDBServerName = $LogDBServerName;
        LogDBName = $LogDBName;
        LogTableName = 'SiteLogTable';
        LogDBUserName = $LogDBUserName;
        ContainerURL = "$($StorageContext.BlobEndPoint)public"
    }
    
    $Configurations | ConvertTo-Json  | Out-File -FilePath "$($ConfigurationFolderPath)\ConfigDetails.json"
}

function Deploy-WebService {
    param (
        $ConfigurationFolderPath
    )

    $Configurations = Get-Content "$($ConfigurationFolderPath)\ConfigDetails.json" | ConvertFrom-Json -AsHashtable
    
    $Password = (Get-AzKeyVaultSecret -VaultName $Configurations['KeyValtName'] -Name $Configurations['VmSecretName']).SecretValue
    #Deploy resources
    $DeploymentOutput = New-AzResourceGroupDeployment -ResourceGroupName $Configurations['ResosurceGroup'] `
            -Name ($Configurations['ResosurceGroup']+"_web_"+(Get-Date -Format "dd-MM-yy_HH-mm")) `
            -TemplateFile "$($Configurations['ExtractFolderLocation'])\DeploymentTemplates\Template.json" `
            -TemplateParameterFile "$($Configurations['ExtractFolderLocation'])\DeploymentTemplates\Template.parameters.json" `
            -ResourcePrefix $Configurations['ResourcePrefix'] `
            -Password $Password `
            -StorageAccountName $Configurations['StorageAccountName'] `
            -StorageContainerSASKey $Configurations['StorageAccountSASKey'] `
            -ContainerUrl $Configurations['ContainerURL'] 
    
    $OutputValues = $DeploymentOutput.Outputs

    $Configurations += @{
        VMCount = $OutputValues['numberOfVMInstances'].value;
        DomainName = $OutputValues['publicIpFQDN'].value;
        VmUserName = $OutputValues['vmUsername'].value;
        HostFilePath = "$($ConfigurationFolderPath)\HostConfig"
    }
    
    $Configurations | ConvertTo-Json  | Out-File -FilePath "$($ConfigurationFolderPath)\ConfigDetails.json"

    Write-HostInformation -HostFilePath "$($ConfigurationFolderPath)\HostConfig" `
                        -HostDNSName $Configurations['DomainName'] `
                        -HostCount $Configurations['VMCount']
}

function Write-HostInformation {
    param (
        $HostFilePath,
        $HostDNSName,
        $HostCount
    )
    
    $StartPort = 220

    $hostPorts = @()
    for ($i = 0; $i -lt $HostCount; $i++) {
        $hostPorts += "$($HostDNSName):$($StartPort+$i)"
    }
    $hostPorts | Out-File -FilePath $HostFilePath
}

function Remove-StorageContainer {
    param (
        $ConfigurationFolderPath
    )

    Write-Host 'Removing Storage Containers'

    $Configurations = Get-Content "$($ConfigurationFolderPath)\ConfigDetails.json" | ConvertFrom-Json -AsHashtable
    $StorageContext = New-AzStorageContext -StorageAccountName $Configurations['StorageAccountName'] -StorageAccountKey $Configurations['StorageAccountKey']
    Remove-AzStorageContainer -Name 'public' -Context $StorageContext -Force 
    Remove-AzStorageContainer -Name 'private' -Context $StorageContext -Force 

    $Configurations.Remove('ContainerURL')
    $Configurations.Remove('StorageAccountSASKey')

    $Configurations | ConvertTo-Json  | Out-File -FilePath "$($ConfigurationFolderPath)\ConfigDetails.json"
}

#Create Slots to fill by user 
function Add-Parameters {
    param (
        $ConfigurationFolderPath
    )
    $Configurations = Get-Content "$($ConfigurationFolderPath)\ConfigDetails.json" | ConvertFrom-Json -AsHashtable

    $Configurations += @{
        FromEmailAddress = Read-Host -Prompt 'From Email Address';
        FromEmailUserName = Read-Host -Prompt 'From Email Address Username';
        ToEmailAddress = Read-Host -Prompt 'To Email Address';
    }
    
    $Configurations | ConvertTo-Json  | Out-File -FilePath "$($ConfigurationFolderPath)\ConfigDetails.json"
}

Set-Environment -WorkSpace $WorkSpace `
                    -ExtractFolderLocation $ExtractFolderLocation `
                    -ResourceGroupName $ResourceGroupName `
                    -ResourceGroupLocation $ResourceGroupLocation `
                    -KeyValtName $KeyValtName `
                    -VmSecretName $VmSecretName `
                    -EmailSecretName $EmailSecretName
