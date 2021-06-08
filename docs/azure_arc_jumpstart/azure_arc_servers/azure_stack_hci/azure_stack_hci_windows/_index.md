---
type: docs
title: "Windows Server Virtual Machine"
linkTitle: "Windows Server Virtual Machine"
weight: 1
description: >
---

## Deploy a Windows Server Virtual Machine and connect it to Azure Arc using Powershell

The following README will guide you on how to automatically onboard a Azure Windows VM on to Azure Arc using [Azure ARM Template](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/overview). The provided ARM template is responsible of creating the Azure resources as well as executing the Azure Arc onboard script on the VM.

The following README will guide you on how to use the provided PowerShell script to deploy a Windows Server Virtual Machine on an [Azure Stack HCI](https://docs.microsoft.com/en-us/azure-stack/hci/overview) cluster and connected it as an Azure Arc enabled server.

This guide will **not** provide instructions on how to deploy and set up Azure Stack HCI and it assumes you already have a configured cluster. The commands described in this guide should be ran on the management computer or in a host server in a cluster.

> **Note: In this scenario, we will create a Virtual Machine on an Azure Stack HCI node, since this is for demo and testing purposes. For production scenarios, it can be a good practice to create a server cluster for guaranteeing high availability ????????????**

## Prerequisites

* Enable subscription with the resource provider for Azure Arc enabled Servers. Registration is an asynchronous process, and registration may take approximately 10 minutes.

  ```powershell
  Register-AzResourceProvider -ProviderNamespace Microsoft.HybridCompute
  Get-AzResourceProvider -ListAvailable | Select-Object ProviderNamespace, RegistrationState | Select-String  -Pattern "Microsoft.HybridCompute"
  ```

* Create Azure service principal (SP)

    To be able to complete the scenario and its related automation, an Azure service principal assigned with the “Contributor” role is required. To create it, login to your Azure account using PowerShell and run the below command. To do this, you will need to run the script from a PowerShell session that has access to your AKS on the Azure Stack HCI environment.

    ```powershell
    Connect-AzAccount
    $sp = New-AzADServicePrincipal -DisplayName "<Unique SP Name>" -Role 'Contributor'
    ```

    For example:

    ```powershell
    $sp = New-AzADServicePrincipal -DisplayName "<Unique SP Name>" -Role 'Contributor'
    ```

    This command will create a variable with a secure string as shown below:

    ```shell
    Secret                : System.Security.SecureString
    ServicePrincipalNames : {XXXXXXXXXXXXXXXXXXXXXXXXXXXX, http://AzureArcHCIVM}
    ApplicationId         : XXXXXXXXXXXXXXXXXXXXXXXXXXXX
    ObjectType            : ServicePrincipal
    DisplayName           : AzureArcK8s
    Id                    : XXXXXXXXXXXXXXXXXXXXXXXXXXXX
    Type                  :
    ```

    To expose the generated password use this code to export the secret:

    ```powershell
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp.Secret)
    $UnsecureSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    ```

    Copy the Service Principal ApplicationId and Secret as you will need it for later on in the automation.

    > **Note: It is optional but highly recommended to scope the SP to a specific [Azure subscription and resource group](https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azadserviceprincipal?view=azps-5.4.0)**

## Automation Flow

For you to get familiar with the automation and deployment flow, below is an explanation.

1. User is editing the PowerShell script environment variables (1-time edit). These variables values are being used throughout the deployment and Azure Arc onboarding.

2. User is running the PowerShell script to deploy a basic Windows Server Virtual Machine on Azure Stack HCI and onboard onto Azure Arc. Runtime script will:
    * Download ISO filee
    * Creation of a new Virtual Switch
    * Creation of a new VM
    * Onboard to Azure Arc (script). CAN I DO IT DIRECTLY DURING VM CREATION?

3. In order to allow the Azure VM to successfully be projected as an Azure Arc enabled server, the script will:

    1. Set local OS environment variables.

    2. Generate a local OS logon script named *LogonScript.ps1*. This script will:

        * Create the *LogonScript.log* file.

        * Stop and disable the "Windows Azure Guest Agent" service.

        * Create a new Windows Firewall rule to block Azure IMDS outbound traffic to the *169.254.169.254* remote address.

        * Unregister the logon script Windows schedule task so it will not run after first login.

    3. Disable and prevent Windows Server Manager from running on startup.

4. User RDP to Windows VM which will start the *LogonScript* script execution and will onboard the VM to Azure Arc.

## Deployment

As mentioned, this deployment will leverage ARM templates. You will deploy a single template, responsible for creating all the Azure resources in a single resource group as well onboarding the created VM to Azure Arc.

* Before deploying the ARM template, login to Azure using Azure CLI with the ```az login``` command.

* The deployment is using the ARM template parameters file. Before initiating the deployment, edit the [*azuredeploy.parameters.json*](https://github.com/microsoft/azure_arc/blob/main/azure_arc_servers_jumpstart/azure/windows/arm_template/azuredeploy.parameters.json) file located in your local cloned repository folder. An example parameters file is located [here](https://github.com/microsoft/azure_arc/blob/main/azure_arc_servers_jumpstart/azure/windows/arm_template/azuredeploy.parameters.example.json).

* To deploy the ARM template, navigate to the local cloned [deployment folder](https://github.com/microsoft/azure_arc/tree/main/azure_arc_servers_jumpstart/azure/windows/arm_template) and run the below command:

    ```shell
    az group create --name <Name of the Azure resource group> --location <Azure Region> --tags "Project=jumpstart_azure_arc_servers"
    az deployment group create \
    --resource-group <Name of the Azure resource group> \
    --name <The name of this deployment> \
    --template-uri https://raw.githubusercontent.com/microsoft/azure_arc/main/azure_arc_servers_jumpstart/azure/windows/arm_template/azuredeploy.json \
    --parameters <The *azuredeploy.parameters.json* parameters file location>
    ```

    > **Note: Make sure that you are using the same Azure resource group name as the one you've just used in the *azuredeploy.parameters.json* file**

    For example:

    ```shell
    az group create --name Arc-Servers-Win-Demo --location "East US" --tags "Project=jumpstart_azure_arc_servers"
    az deployment group create \
    --resource-group Arc-Servers-Win-Demo \
    --name arcwinsrvdemo \
    --template-uri https://raw.githubusercontent.com/microsoft/azure_arc/main/azure_arc_servers_jumpstart/azure/windows/arm_template/azuredeploy.json \
    --parameters azuredeploy.parameters.json
    ```

* Once Azure resources has been provisioned, you will be able to see it in Azure portal.

    ![Screenshot ARM template output](./01.jpg)

    ![Screenshot resources in resource group](./02.jpg)

## Windows Login & Post Deployment

* Now that the Windows Server VM is created, it is time to login to it. Using its public IP, RDP to the VM.

    ![Screenshot Azure VM public IP address](./03.jpg)

* At first login, as mentioned in the "Automation Flow" section, a logon script will get executed. This script was created as part of the automated deployment process.

* Let the script to run its course and **do not close** the Powershell session, this will be done for you once completed.

    > **Note: The script run time is ~1-2min long.**

    ![Screenshot script output](./04.jpg)

    ![Screenshot script output](./05.jpg)

    ![Screenshot script output](./06.jpg)

    ![Screenshot script output](./07.jpg)

* Upon successful run, a new Azure Arc enabled server will be added to the resource group.

![Screenshot Azure Arc enabled server on resource group](./08.jpg)

![Screenshot Azure Arc enabled server details](./09.jpg)

## Cleanup

To delete the entire deployment, simply delete the resource group from the Azure portal.

![Screenshot delete resource group](./10.jpg)
