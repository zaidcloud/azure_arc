---
type: docs
title: "Key Vault"
linkTitle: "Key Vault"
weight: 4
description: >
---

## Deploy Monitoring Agent Extension to Azure Arc Linux and Windows servers using Azure Policy

The scenario will show you how to onboard the [Azure Key Vault](https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/key-vault-windows) extension on an Azure Arc enabled Server, and then use a certificate managed by keyvault to secure web traffic with TLS on a web server. In this guide, we will focus on securing an Ubuntu web server. The only prerequiste you need to complete this scenario is an existing Azure Arc enabled server running Ubuntu 18.04 (other Ubuntu releases may also work but have not been tested).

**If you don't yet have an Ubuntu server that is Azure Arc enabled, this repository offers you a way to do so in an automated fashion. Complete one of the scenarios below before proceeding:**

* **[GCP Ubuntu VM](gcp_terraform_ubuntu.md)**
* **[AWS Ubuntu VM](aws_terraform_ubuntu.md)**
* **[Azure Ubuntu VM](azure_arm_template_linux.md)**
* **[VMware Ubuntu VM](vmware_terraform_ubuntu.md)**
* **[Local Ubuntu VM](local_vagrant_ubuntu.md)**

## Prerequisites

* Clone this repo

    ```console
    git clone https://github.com/microsoft/azure_arc.git
    ```

* As mentioned, this guide starts at the point where you already deployed and connected VMs or bare-metal servers to Azure Arc. For this scenario, as can be seen in the screenshots below, we will be using an Amazon Web Services (AWS) EC2 instance that has been already connected to Azure Arc and is visible as a resource in Azure.

    ![Screenshot showing EC2 instance in AWS console](./01.png)

    ![Screenshot showing Azure Arc enabled server](./02.png)

* [Install or update Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest). Azure CLI should be running version 2.15 or later. Use ```az --version``` to check your current installed version.

## Create an Azure Keyvault and a new self-signed certificate

First, we will create a new Azure resource group, Azure Keyvault and a self-signed certificate from an Az CLI.

* Create a new resource group to hold the keyvault.

    ```console
    az group create --name <name for your resource group> --location <location for your resource group>
    ```

    ![Screenshot of creating a resource group from Az CLI](./03.png)

* Create a new keyvault. Note that keyvault names must be globally unique.

    ```console
    az keyvault create --name <name for your keyvault> --location <location> --resource-group <name of your resource group>
    ```

    ![Screenshot of creating a keyvault from Az CLI](./04.png)

* Create a new self-signed certificate with keyvault.

    ```console
    az keyvault certificate create --vault-name arckeyvault1 -n cert1 -p "$(az keyvault certificate get-default-policy)"
    ```

    ![Screenshot of creating a self-signed certificate from Az CLI](./05.png)

## Install and configure Nginx on your Azure Arc enabled Ubuntu server

We will use the Azure Custom Script extension on your Azure Arc enabled server to install and configure an Nginx web server. Before installing Nginx, we must open the right inbound ports on our AWS EC2 instance's security group. Then we will deploy an ARM template that will use the custom script extension to install Nginx.

* Navigate to your EC2 instance on the AWS cloud console and open the "allow-all-sg" security group.

    ![Screenshot of an EC2 instance in AWS cloud console](./06.png)

* Click on the "Inbound" tab of the security group and then click "Edit".

    ![Screenshot of a security group in AWS cloud console](./07.png)

    ![Screenshot of a security group in AWS cloud console](./08.png)

* Click "Add Rule" and add HTTP and HTTPS rules, keeping all the default seeings as seen in the screenshot. Click Save.

    ![Screenshot of adding a security group rule in AWS cloud console](./09.png)

    ![Screenshot of added a security group rule in AWS cloud console](./10.png)

* Use Custom Script extension to install Nginx
