---
type: docs
title: "Integrate Open Service Mesh (OSM) with Cluster API as an Azure Arc Connected Cluster using Kubernetes extensions"
linkTitle: "Integrate Open Service Mesh with Cluster API as an Azure Arc Connected Cluster using Kubernetes extensions"
weight: 2
description: >
---

## Integrate Open Service Mesh (OSM) with Cluster API as an Azure Arc Connected Cluster using Kubernetes extensions

The following README will guide you on how to enable [Open Service Mesh](https://openservicemesh.io/) for a Cluster API that is projected as an Azure Arc connected cluster.

In this guide, you will hook the Cluster API to Open Service Mesh by deploying the [Open Service Mesh extension](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-arc-enabled-osm) on your Kubernetes cluster in order to start collecting security related logs and telemetry.  

> **Note: This guide assumes you already deployed a Cluster API and connected it to Azure Arc. If you haven't, this repository offers you a way to do so in an automated fashion using a [Shell script](https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_k8s/cluster_api/capi_azure/).**

Kubernetes extensions are add-ons for Kubernetes clusters. The extensions feature on Azure Arc enabled Kubernetes clusters enables usage of Azure Resource Manager based APIs, CLI and portal UX for deployment of extension components (Helm charts in initial release) and will also provide lifecycle management capabilities such as auto/manual extension version upgrades for the extensions.

## Prerequisites

* Clone the Azure Arc Jumpstart repository

    ```shell
    git clone https://github.com/microsoft/azure_arc.git
    ```

* [Install or update Azure CLI to version 2.15.0 and above](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest). Use the below command to check your current installed version.

  ```shell
  az --version
  ```

* Create Azure service principal (SP)

    To be able to complete the scenario and its related automation, Azure service principal assigned with the “Contributor” role is required. To create it, login to your Azure account run the below command (this can also be done in [Azure Cloud Shell](https://shell.azure.com/)).

    ```shell
    az login
    az ad sp create-for-rbac -n "<Unique SP Name>" --role contributor
    ```

    For example:

    ```shell
    az ad sp create-for-rbac -n "http://AzureArcK8s" --role contributor
    ```

    Output should look like this:

    ```json
    {
    "appId": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "displayName": "AzureArcK8s",
    "name": "http://AzureArcK8s",
    "password": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "tenant": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
    ```

    > **Note: The Jumpstart scenarios are designed with as much ease of use in-mind and adhering to security-related best practices whenever possible. It is optional but highly recommended to scope the service principal to a specific [Azure subscription and resource group](https://docs.microsoft.com/en-us/cli/azure/ad/sp?view=azure-cli-latest) as well considering using a [less privileged service principal account](https://docs.microsoft.com/en-us/azure/role-based-access-control/best-practices)**

## Automation Flow

For you to get familiar with the automation and deployment flow, below is an explanation.

* User has deployed Kubernetes using Cluster API and has it connected as Azure Arc enabled Kubernetes cluster.

* User is editing the environment variables on the Shell script file (1-time edit) which then be used throughout the extension deployment.

* User will set the current kubectl context to the connected Azure Arc enabled Kubernetes cluster.

* User is running the shell script. The script will use the extension management feature of Azure Arc to deploy the Open Service Mesh extension on the Azure Arc connected cluster.

* User is veryfing the cluster and make sure OSM extension enabled.

* User is simulating a monitoring scenario, by deploying the a sample app to Azure Arc enabled Kuberentes cluster.

* User check the monitoring insights to confirm OSM start capturing the logs and metrics from the custom app sending it over to Azure Monitor.

## Create Open Service Mesh extensions instance

To create a new extension Instance, we will use the _k8s-extension create_ command while passing in values for the mandatory parameters. This scenario provides you with the automation to deploy the Open Service Mesh extension on your Azure Arc enabled Kubernetes cluster.

* Before integrating the cluster with Open Service Mesh, make sure that the kubectl context is pointing to your Azure Arc enabled Kubernetes cluster. Also notice that, there is no any extensions enabled yet in your Arc enabled Kuberentes cluster.

    ![Screenshot showing current kubectl context pointing to CAPI cluster](./01.png)

    ![Screenshot showing Azure Portal with Azure Arc enabled Kubernetes resource extensions](./02.png)

* Edit the environment variables in the script to match your environment parameters followed by running the ```. ./capi_osm_extension.sh``` command.

 > **Note: The extra dot is due to the shell script has an *export* function and needs to have the vars exported in the same shell session as the rest of the commands.**

   The script will:

* Login to your Azure subscription using the SPN credentials
* Add or Update your local _connectedk8s_ and _k8s-extension_ Azure CLI extensions
* Create Open Service Mesh k8s extension instance
* Create Azure Monitor k8s extension instance

You can now see that Open Service Mesh & Azure Monitor extensions are enabled once you visit the extension tab section of the Azure Arc enabled Kubernetes cluster resource in Azure.

![Screenshot extension deployment security tab](./03.png)

* You can also verify the deployment by running the command below:

```bash
kubectl get pods -n arc-osm-system
```

![Screenshot extension deployment on cluster](./04.png)

## Simulate Azure Monitoring with a sample app

To verify that Open Service Mesh is working properly, lets deploy a sample app and see the Azure monitoring integration with Open Service Mesh.

There is an automation script provided for the same and you can run ```. ./onboard_osm_test_app.sh``` command.

The script will:

* Download and install OSM cli locally
* Create four namespaces in kubernetes to deploy a test app
* Onboard the Namespaces to the OSM Mesh and enable sidecar injection on the namespaces
* Enable metrics for pods belonging to app namespaces
* Update the namespaces to be monitored by modifying the configmap provided by the OSM
* Deploy the apps to the namespaces

After 15 minutes or so you can verify the integration and moniotring insights coming from OSM to Azure Monitor by following the below steps.

![Show the namespaces in the Container Insights](./05.png)

![Show the report templates for OSM in the Container insights](./06.png)

![Show the log analytics query ](./07.png)

### Delete extension instance

The following command only deletes the extension instances, but doesn't delete the Log Analytics workspace 

```bash
az k8s-extension delete --name [] --cluster-type connectedClusters --cluster-name <cluster-name> --resource-group <resource-group>
```
