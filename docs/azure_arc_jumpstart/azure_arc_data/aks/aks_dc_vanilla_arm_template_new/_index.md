<!-- ---
type: docs
title: "Data Controller ARM Template"
linkTitle: "Data Controller ARM Template"
weight: 1
description: >
--- -->

## Deploy a vanilla Azure Arc Data Controller in directly connected mode on AKS using an ARM Template

The following README will guide you on how to deploy a "Ready to Go" environment so you can start using [Azure Arc enabled data services](https://docs.microsoft.com/en-us/azure/azure-arc/data/overview) deployed on [Azure Kubernetes Service (AKS)](https://docs.microsoft.com/en-us/azure/aks/intro-kubernetes) cluster using [Azure ARM Template](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/overview).

By the end of this guide, you will have an AKS cluster deployed with an Azure Arc Data Controller and a Microsoft Windows Server 2019 (Datacenter) Azure VM, installed & pre-configured with all the required tools needed to work with Azure Arc Data Services.

> **Note: Currently, Azure Arc enabled data services is in [public preview](https://docs.microsoft.com/en-us/azure/azure-arc/data/release-notes)**.

## Prerequisites

* Clone the Azure Arc Jumpstart repository

    ```shell
    git clone https://github.com/microsoft/azure_arc.git
    ```

* [Install or update Azure CLI to version 2.15.0 and above](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest). Use the below command to check your current installed version.

  ```shell
  az --version
  ```

* [Generate SSH Key](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/create-ssh-keys-detailed) (or use existing ssh key).

* Create Azure service principal (SP)

    To be able to complete the scenario and its related automation, Azure service principal assigned with the “Contributor” role is required. To create it, login to your Azure account run the below command (this can also be done in [Azure Cloud Shell](https://shell.azure.com/)).

    ```shell
    az login
    az ad sp create-for-rbac -n "<Unique SP Name>" --role contributor
    ```

    For example:

    ```shell
    az ad sp create-for-rbac -n "http://AzureArcData" --role contributor
    ```

    Output should look like this:

    ```json
    {
    "appId": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "displayName": "AzureArcData",
    "name": "http://AzureArcData",
    "password": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "tenant": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
    ```

    > **Note: It is optional, but highly recommended, to scope the SP to a specific [Azure subscription and resource group](https://docs.microsoft.com/en-us/cli/azure/ad/sp?view=azure-cli-latest).**

## Automation Flow

For you to get familiar with the automation and deployment flow, below is an explanation.

* User is editing the ARM template parameters file (1-time edit). These parameters values are being used throughout the deployment.

* Main [_azuredeploy_ ARM template](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/cluster_api/capi_azure/arm_template/dc_vanilla/azuredeploy.json) will initiate the deployment of the linked ARM templates:

  * [_aks_](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/aks.json) - Deploys the AKS cluster where all the Azure Arc data services will be deployed.
  * [_clientVm_](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/clientVm.json) - Deploys the client Windows VM. This is where all user interactions with the environment are made from.
  * [_logAnalytics_](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/logAnalytics.json) - Deploys Azure Log Analytics workspace to support Azure Arc enabled data services logs uploads.

* User remotes into client Windows VM, which automatically kicks off the [_DataServicesLogonScript_](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/artifacts/DataServicesLogonScript.ps1) PowerShell script that deploy and configure Azure Arc enabled data services on the AKS cluster including the data controller.

## Deployment

As mentioned, this deployment will leverage ARM templates. You will deploy a single template that will initiate the entire automation for this scenario.

* The deployment is using the ARM template parameters file. Before initiating the deployment, edit the [_azuredeploy.parameters.json_](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/azuredeploy.parameters.json) file located in your local cloned repository folder.

  * *sshRSAPublicKey* - Your SSH public key
  * *spnClientId* - Your Azure service principal id
  * *spnClientSecret* - Your Azure service principal secret
  * *spnTenantId* - Your Azure tenant id
  * *windowsAdminUsername* - Client Windows VM Administrator name
  * *windowsAdminPassword* - Client Windows VM Password. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long.
  * *myIpAddress* - Your local public IP address. This is used to allow remote RDP and SSH connections to the client Windows VM and K3s Rancher VM.
  * *logAnalyticsWorkspaceName* - Unique name for the deployment log analytics workspace
  * *deploySQLMI* - Boolean that sets whether or not to deploy SQL Managed Instance, for this data controller only scenario we leave it set to *false*.
  * *deployPostgreSQL* - Boolean that sets whether or not to deploy PostgreSQL Hyperscale, for this data controller only scenario we leave it set to *false*.
  * *kubernetesVersion* - AKS version
  * *dnsPrefix* - AKS unique DNS prefix

* To deploy the ARM template, navigate to the local cloned [deployment folder](https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template) and run the below command:

    ```shell
    az group create --name <Name of the Azure resource group> --location <Azure Region>
    az deployment group create \
    --resource-group <Name of the Azure resource group> \
    --name <The name of this deployment> \
    --template-uri https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/azuredeploy.json \
    --parameters <The *azuredeploy.parameters.json* parameters file location>
    ```

    > **Note: Make sure that you are using the same Azure resource group name as the one you've just used in the _azuredeploy.parameters.json_ file**

    For example:

    ```shell
    az group create --name Arc-Data-Demo --location "East US"
    az deployment group create \
    --resource-group Arc-Data-Demo \
    --name arcdata \
    --template-uri https://github.com/microsoft/azure_arc/blob/main/azure_arc_data_jumpstart/aks/arm_template/azuredeploy.json \
    --parameters azuredeploy.parameters.json
    ```

    > **Note: The deployment time for this scenario can take ~15-20min**

* Once Azure resources has been provisioned, you will be able to see it in Azure portal. At this point, the resource group should have **8 verious Azure resources" deployed.

    ![ARM template deployment completed](./01.jpg)

    ![New Azure resource group with all resources](./02.jpg)

## Windows Login & Post Deployment

Now that both the AKS cluster and the Windows Server VM are created, it is time to login to the Client VM.

* Using it's public IP, RDP to the **Client VM**

    ![Data Client VM public IP](./03.jpg)

* At first login, as mentioned in the "Automation Flow" section, a logon script will get executed. This script was created as part of the automated deployment process.

    Let the script to run its course and **do not close** the PowerShell session, this will be done for you once completed. You will notice that the Azure Arc Data Controller gets deployed on the AKS cluster. **The logon script run time is approximately 10min long**.  

    Once the script will finish it's run, the logon script PowerShell session will be closed and the Azure Arc Data Controller will be deployed on the AKS cluster and be ready to use.

    ![PowerShell logon script run](./04.jpg)

    ![PowerShell logon script run](./05.jpg)

    ![PowerShell logon script run](./06.jpg)

    ![PowerShell logon script run](./07.jpg)

    ![PowerShell logon script run](./08.jpg)

  <!-- > **Note: Currently, Azure Arc enabled data services is in [public preview](https://docs.microsoft.com/en-us/azure/azure-arc/data/release-notes) and features are subject to change. As such, the release being used in this scenario does not support the projection of Azure Arc data services resources in the Azure portal**.

    ![Data Controller in a resource group](./09.jpg)

    ![Data Controller resource](./10.jpg) -->

* Using PowerShell, login to the Data Controller and check it's health using the below commands.

    ```powershell
    azdata login --namespace $env:ARC_DC_NAME
    azdata arc dc status show
    ```

    ![azdata login](./11.jpg)

* Another tool automatically deployed is Azure Data Studio along with the *Azure Data CLI*, the *Azure Arc* and the *PostgreSQL* extensions. Using the Desktop shortcut created for you, open Azure Data Studio and click the Extensions settings to see both extensions.

  ![Azure Data Studio shortcut](./12.jpg)

  ![Azure Data Studio extension](./13.jpg)

## Cleanup

* To delete the Azure Arc Data Controller and all of it's Kubernetes resources, run the *DC_Cleanup.ps1* PowerShell script located in *C:\tmp* on the Windows Client VM. At the end of it's run, the script will close all PowerShell sessions. **The Cleanup script run time is approximately 5min long**.

    ![DC_Cleanup PowerShell script run](./14.jpg)

* If you want to delete the entire environment, simply delete the deployment resource group from the Azure portal.

    ![Delete Azure resource group](./15.jpg)

## Re-Deploy Azure Arc Data Controller

In case you deleted the Azure Arc Data Controller from the AKS cluster, you can re-deploy it by running the *DC_Deploy.ps1* PowerShell script located in *C:\tmp* on the Windows Client VM. **The Deploy script run time is approximately 5-10min long**

![Re-Deploy Azure Arc Data Controller PowerShell script](./16.jpg)
