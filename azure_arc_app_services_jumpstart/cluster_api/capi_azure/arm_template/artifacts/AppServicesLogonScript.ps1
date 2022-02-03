Start-Transcript -Path C:\Temp\AppServicesLogonScript.log

$Env:TempDir = "C:\Temp"
$Env:TempLogsDir = "C:\Temp\Logs"
$connectedClusterName = $Env:capiArcAppSvcClusterName
$ArcAppSvcExtensionVersion = "0.12.0"
$storageClassName = "managed-premium"
$namespaceName="appservices"
$extensionName = "arc-app-services"

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Required for azcopy
$azurePassword = ConvertTo-SecureString $Env:spnClientSecret -AsPlainText -Force
$psCred = New-Object System.Management.Automation.PSCredential($Env:spnClientId , $azurePassword)
Connect-AzAccount -Credential $psCred -TenantId $Env:spnTenantId -ServicePrincipal

# Login as service principal
az login --service-principal --username $Env:spnClientId --password $Env:spnClientSecret --tenant $Env:spnTenantId

# Set default subscription to run commands against
# "subscriptionId" value comes from clientVM.json ARM template, based on which 
# subscription user deployed ARM template to. This is needed in case Service 
# Principal has access to multiple subscriptions, which can break the automation logic
az account set --subscription $Env:subscriptionId

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

# Downloading CAPI Kubernetes cluster kubeconfig file
Write-Host "Downloading CAPI Kubernetes cluster kubeconfig file"
$sourceFile = "https://$Env:stagingStorageAccountName.blob.core.windows.net/staging-capi/config"
$context = (Get-AzStorageAccount -ResourceGroupName $Env:resourceGroup).Context
$sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
$sourceFile = $sourceFile + $sas
azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "C:\Users\$Env:USERNAME\.kube\config"

# Downloading 'installCAPI.log' log file
Write-Host "Downloading 'installCAPI.log' log file"
$sourceFile = "https://$Env:stagingStorageAccountName.blob.core.windows.net/staging-capi/installCAPI.log"
$sourceFile = $sourceFile + $sas
azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "$Env:TempLogsDir\installCAPI.log"

Write-Host "`n"
Write-Host "Checking kubernetes nodes"
Write-Host "`n"
kubectl get nodes
Write-Host "`n"

# Localize kubeconfig
$Env:KUBECONTEXT = kubectl config current-context
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

Start-Sleep -Seconds 10
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n appservices; Start-Sleep -Seconds 5; Clear-Host }}

# Deploying Azure App environment
Write-Host "Deploying Azure App Service Kubernetes environment. Hold tight, this might take a few minutes..."
Write-Host "`n"

$kubeEnvironmentName=$connectedClusterName
$workspaceId = $(az resource show --resource-group $Env:resourceGroup --name $Env:logAnalyticsWorkspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
$workspaceKey = $(az monitor log-analytics workspace get-shared-keys --resource-group $Env:resourceGroup --workspace-name $Env:logAnalyticsWorkspaceName --query primarySharedKey -o tsv)
$logAnalyticsWorkspaceIdEnc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workspaceId))
$logAnalyticsKeyEnc = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workspaceKey))

az k8s-extension create `
   --resource-group $Env:resourceGroup `
   --name $extensionName `
   --cluster-type connectedClusters `
   --cluster-name $connectedClusterName `
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
   --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.customerId=${logAnalyticsWorkspaceIdEnc}" `
   --configuration-protected-settings "logProcessor.appLogs.logAnalyticsConfig.sharedKey=${logAnalyticsKeyEnc}"

$extensionId=$(az k8s-extension show `
   --cluster-type connectedClusters `
   --cluster-name $connectedClusterName `
   --resource-group $Env:resourceGroup `
   --name $extensionName `
   --query id `
   --output tsv)

Do {
   Write-Host "Waiting for Azure Arc-enabled app services extension to install. Hold tight, this might take a few minutes...(60s sleeping loop)"
   Start-Sleep -Seconds 60
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
$connectedClusterId = az connectedk8s show --name $connectedClusterName --resource-group $Env:resourceGroup --query id -o tsv
$extensionId = az k8s-extension show --name $extensionName --cluster-type connectedClusters --cluster-name $connectedClusterName --resource-group $Env:resourceGroup --query id -o tsv
$customLocationId = $(az customlocation create --name 'jumpstart-cl' --resource-group $Env:resourceGroup --namespace $namespaceName --host-resource-id $connectedClusterId --cluster-extension-ids $extensionId --kubeconfig "C:\Users\$Env:USERNAME\.kube\config" --query id -o tsv)
Write-Host "`n"
Write-Host "Waiting for 30s before creating the App Services kube environment"
Write-Host "`n"
Start-Sleep -Seconds 30
az appservice kube create --resource-group $Env:resourceGroup --name $kubeEnvironmentName --custom-location $customLocationId

Do {
   Write-Host "Waiting for kube environment to become available. Hold tight, this might take a few minutes...(30s sleeping loop)"
   Start-Sleep -Seconds 30
   $kubeEnvironmentNameStatus = $(if(az appservice kube show --resource-group $Env:resourceGroup --name $kubeEnvironmentName --only-show-errors| Select-String '"provisioningState": "Succeeded"' -Quiet){"Ready!"}Else{"Nope"})
   } while ($kubeEnvironmentNameStatus -eq "Nope")

# Deploying Azure Arc-enabled app services based on user selection   
if ( $Env:deployAppService -eq $true )
{
    & "$Env:TempDir\deployAppService.ps1"
}

if ( $Env:deployFunction -eq $true )
{
    & "$Env:TempDir\deployFunction.ps1"
}

if ( $Env:deployLogicApp -eq $true )
{
    & "$Env:TempDir\deployLogicApp.ps1"
}

if ( $Env:deployApiMgmt -eq $true )
{
    & "$Env:TempDir\deployApiMgmt.ps1"
}

# Changing to Client VM wallpaper
$imgPath="C:\Temp\wallpaper.png"
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
