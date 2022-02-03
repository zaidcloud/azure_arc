Start-Transcript -Path C:\Temp\AppServicesLogonScript.log

$Env:TempDir = "C:\Temp"
$Env:TempLogsDir = "C:\Temp\Logs"
$ArcAppSvcExtensionVersion = "0.12.0"
$storageClassName = "default"
$namespaceName="appservices"
$extensionName = "arc-app-services"

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

az login --service-principal --username $Env:spnClientId --password $Env:spnClientSecret --tenant $Env:spnTenantId
Write-Host "`n"

# Deploying AKS cluster
Write-Host "Deploying AKS cluster"
Write-Host "`n"
az aks create --resource-group $Env:resourceGroup `
              --name $Env:clusterName `
              --location $Env:azureLocation `
              --kubernetes-version $Env:kubernetesVersion `
              --dns-name-prefix $Env:dnsPrefix `
              --enable-aad `
              --enable-azure-rbac `
              --generate-ssh-keys `
              --tags "Project=jumpstart_azure_arc_app_services" `
              --enable-addons monitoring

az aks get-credentials --resource-group $Env:resourceGroup `
                       --name $Env:clusterName `
                       --admin

$aksResourceGroupMC = $(az aks show --resource-group $Env:resourceGroup --name $Env:clusterName -o tsv --query nodeResourceGroup)

Write-Host "`n"
Write-Host "Checking kubernetes nodes"
Write-Host "`n"
kubectl get nodes

# # Creating Azure Public IP resource to be used by the Azure Arc app service
# Write-Host "`n"
# Write-Host "Creating Azure Public IP resource to be used by the Azure Arc app service"
# Write-Host "`n"
# az network public-ip create --resource-group $aksResourceGroupMC --name "Arc-AppSvc-PIP" --sku STANDARD
# $staticIp = $(az network public-ip show --resource-group $aksResourceGroupMC --name "Arc-AppSvc-PIP" --output tsv --query ipAddress)

# Registering Azure Arc providers
Write-Host "`n"
Write-Host "Registering Azure Arc providers, hold tight..."
Write-Host "`n"
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait
az provider register --namespace Microsoft.Web --wait

az provider show --namespace Microsoft.Kubernetes -o table
Write-Host "`n"
az provider show --namespace Microsoft.KubernetesConfiguration -o table
Write-Host "`n"
az provider show --namespace Microsoft.ExtendedLocation -o table
Write-Host "`n"
az provider show --namespace Microsoft.Web -o table
Write-Host "`n"

# Making extension install dynamic
az config set extension.use_dynamic_install=yes_without_prompt

# Installing Azure Arc CLI extensions
Write-Host "Installing Azure Arc CLI extensions"
Write-Host "`n"
az extension add --name "connectedk8s" -y
az extension add --name "k8s-extension" -y
az extension add --name "customlocation" -y
az extension add --name "appservice-kube" -y

Write-Host "`n"
az -v

# Onboarding the cluster as an Azure Arc-enabled Kubernetes cluster
Write-Host "`n"
Write-Host "Onboarding the cluster as an Azure Arc-enabled Kubernetes cluster"
Write-Host "`n"

# Localize kubeconfig
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

# Create Kubernetes - Azure Arc Cluster
az connectedk8s connect --name $Env:clusterName `
                        --resource-group $Env:resourceGroup `
                        --location $Env:azureLocation `
                        --tags 'Project=jumpstart_azure_arc_app_services' `
                        --kube-config $Env:KUBECONFIG `
                        --kube-context $Env:KUBECONTEXT

Start-Sleep -Seconds 10
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n appservices; Start-Sleep -Seconds 5; Clear-Host }}

# Deploying Azure App environment
Write-Host "`n"
Write-Host "Deploying Azure App Service Kubernetes environment"
Write-Host "`n"

$kubeEnvironmentName=$Env:clusterName
$workspaceId = $(az resource show --resource-group $Env:resourceGroup --name $Env:workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
$workspaceKey = $(az monitor log-analytics workspace get-shared-keys --resource-group $Env:resourceGroup --workspace-name $Env:workspaceName --query primarySharedKey -o tsv)
$logAnalyticsWorkspaceIdEnc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workspaceId))
$logAnalyticsKeyEnc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workspaceKey))

az k8s-extension create `
    --resource-group $Env:resourceGroup `
    --name $extensionName `
    --cluster-type connectedClusters `
    --cluster-name $Env:clusterName `
    --extension-type 'Microsoft.Web.Appservice' `
    --release-train stable `
    --version $ArcAppSvcExtensionVersion `
    --auto-upgrade-minor-version false `
    --scope cluster `
    --release-namespace $namespaceName `
    --configuration-settings "Microsoft.CustomLocation.ServiceAccount=default" `
    --configuration-settings "appsNamespace=${namespaceName}" `
    --configuration-settings "clusterName=${kubeEnvironmentName}" `
    --configuration-settings "keda.enabled=true" `
    --configuration-settings "buildService.storageClassName=${storageClassName}" `
    --configuration-settings "buildService.storageAccessMode=ReadWriteOnce" `
    --configuration-settings "customConfigMap=${namespaceName}/kube-environment-config" `
    --configuration-settings "logProcessor.appLogs.destination=log-analytics" `
    --configuration-settings "envoy.annotations.service.beta.kubernetes.io/azure-load-balancer-resource-group=$aksResourceGroupMC" `
    --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.customerId=${logAnalyticsWorkspaceIdEnc}" `
    --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.sharedKey=${logAnalyticsKeyEnc}"

$extensionId=$(az k8s-extension show `
    --cluster-type connectedClusters `
    --cluster-name $Env:clusterName `
    --resource-group $Env:resourceGroup `
    --name $extensionName `
    --query id `
    --output tsv)

# az resource wait --ids $extensionId --api-version 2020-07-01-preview --custom "properties.installState!='Pending'"

Do {
    Write-Host "Waiting for Azure Arc-enabled app services extension to install. Hold tight, this might take a few minutes...(45s sleeping loop)"
    Start-Sleep -Seconds 45
    $extensionIdStatus = $(if(az resource show --ids $extensionId | Select-String '"provisioningState": "Succeeded"' -Quiet){"Ready!"}Else{"Nope"})
    } while ($extensionIdStatus -eq "Nope")

Do {
    Write-Host "Waiting for build service to become available. Hold tight, this might take a few minutes...(30s sleeping loop)"
    Start-Sleep -Seconds 30
    $buildService = $(if(kubectl get pods -n appservices | Select-String "k8se-build-service" | Select-String "Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($buildService -eq "Nope")
    
    Do {
    Write-Host "Waiting for log-processor to become available. Hold tight, this might take a few minutes...(30s sleeping loop)"
    Start-Sleep -Seconds 30
    $logProcessorStatus = $(if(kubectl describe daemonset ($extensionName + "-k8se-log-processor") -n appservices | Select-String "Pods Status:  4 Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($logProcessorStatus -eq "Nope")

# Deploying App Service Kubernetes Environment
Write-Host "`n"
Write-Host "Deploying App Service Kubernetes Environment. Hold tight, this might take a few minutes..."
Write-Host "`n"
$connectedClusterId = az connectedk8s show --name $Env:clusterName --resource-group $Env:resourceGroup --query id -o tsv
$extensionId = az k8s-extension show --name $extensionName --cluster-type connectedClusters --cluster-name $Env:clusterName --resource-group $Env:resourceGroup --query id -o tsv
$customLocationId = $(az customlocation create --name 'jumpstart-cl' --resource-group $Env:resourceGroup --namespace appservices --host-resource-id $connectedClusterId --cluster-extension-ids $extensionId --kubeconfig "C:\Users\$Env:USERNAME\.kube\config" --query id -o tsv)
az appservice kube create --resource-group $Env:resourceGroup --name $kubeEnvironmentName --custom-location $customLocationId --static-ip "$staticIp" --location $Env:azureLocation --output none 

Do {
   Write-Host "Waiting for kube environment to become available. Hold tight, this might take a few minutes..."
   Start-Sleep -Seconds 15
   $kubeEnvironmentNameStatus = $(if(az appservice kube show --resource-group $Env:resourceGroup --name $kubeEnvironmentName | Select-String '"provisioningState": "Succeeded"' -Quiet){"Ready!"}Else{"Nope"})
   } while ($kubeEnvironmentNameStatus -eq "Nope")

if ( $Env:deployAppService -eq $true )
{
    & "$Env:TempDir\deployAppService.ps1"
}

if ( $Env:deployFunction -eq $true )
{
    & "$Env:TempDir\deployFunction.ps1"
}


if ( $Env:deployApiMgmt -eq $true )
{
    & "$Env:TempDir\deployApiMgmt.ps1"
}

if ( $Env:deployLogicApp -eq $true )
{
    & "$Env:TempDir\deployLogicApp.ps1"
}

# Changing to Client VM wallpaper
$imgPath="$Env:TempDir\wallpaper.png"
$code = @' 
using System.Runtime.InteropServices; 
namespace Win32{ 
    
     public class Wallpaper{ 
        [DllImport("user32.dll", CharSet=CharSet.Auto)] 
         static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ; 
         
         public static void SetWallpaper(string thePath){ 
            SystemParametersInfo(20,0,thePath,3); 
         }
    }
 } 
'@

add-type $code 
[Win32.Wallpaper]::SetWallpaper($imgPath)

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "AppServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5
