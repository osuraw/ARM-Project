# Setup Environment
## Software packages and modules needed 
- PowerShell 7 [Download](https://github.com/PowerShell/PowerShell/releases/tag/v7.1.3)
    - Install-Module -Name Az
    - Install-Module -Name SqlServer
- Open-SSH client (pre-installed in Windows 10)
- Download and extract project folder 
## Azure pre-setup
- Azure Account login or Service Principle to access resources
- Azure key vault with two secrets
    - Secret 1: VM password
    - Secret 2: Email account password
## Execute Scripts
### Deploy Resources to Azure
- Open PowerShell and navigate to extract folder
- Run DeployResources.ps1 with below parametes
    - WorkSpace: New fodler "**_ResoureGroupName-ResourceGroupLocation_**" will created in this location
    - ExtractFolderLocation: Location of the extracted file
    - ResourceGroupName: Name of the resource group (*No number, Max 16 characters*)
    - ResourceGroupLocation: Location where resources get deployed
    - KeyValtName: name of the Azure Key-Vault
    - VmSecretName: secret name for VM passwords
    - EmailSecretName: secret name for Email password

    ``` PowerShell
    DeployResources.ps1 -WorkSpace '' `
                    -ExtractFolderLocation '' `
                    -ResourceGroupName '' `
                    -ResourceGroupLocation '' `
                    -KeyValtName '' `
                    -VmSecretName '' `
                    -EmailSecretName '' 
    ```
- Supply Required value when asked
    - From Email address
    - From Email address username
    - To Email address

### Run Service Management Scripts
- Create two tasks using Windows Task Scheduler
- Scrips located at: *Extracted folder/ServiceManagementScripts*
- Task 1: Collect logs
    - Parameters
        - Workspace: "**_workspace path in previous step/ResoureGroupName-ResourceGroupLocation_**"
    ```PowerShell
    HandleLogs.ps1 -WorkSpace ''
    ```
- Task 2: Check Service Health 
    - Parameters
        - Workspace: "**_workspace path used in previous step /ResoureGroupName-ResourceGroupLocation_**"
    ```PowerShell
    CheckWebServiceHealth.ps1 -WorkSpace ''
    ```

![Architecture Diagram]('architecture.png')