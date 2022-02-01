Start-Transcript -Path C:\Temp\deployLogicApp.log

# Downloading sample Logic App
Invoke-WebRequest ($Env:templateBaseUrl + "artifacts/logicAppCode/CreateBlobFromQueueMessage/workflow.json") -OutFile (New-Item -Path "C:\Temp\logicAppCode\CreateBlobFromQueueMessage\workflow.json" -Force)
Invoke-WebRequest ($Env:templateBaseUrl + "artifacts/logicAppCode/connections.json") -OutFile (New-Item -Path "C:\Temp\logicAppCode\connections.json" -Force)
Invoke-WebRequest ($Env:templateBaseUrl + "artifacts/logicAppCode/host.json") -OutFile (New-Item -Path "C:\Temp\logicAppCode\host.json" -Force)
Invoke-WebRequest ($Env:templateBaseUrl + "artifacts/ARM/connectors-parameters.json") -OutFile (New-Item -Path "C:\Temp\ARM\connectors-parameters.json" -Force)
Invoke-WebRequest ($Env:templateBaseUrl + "artifacts/ARM/connectors-template.json") -OutFile (New-Item -Path "C:\Temp\ARM\connectors-template.json" -Force)

# Creating Azure Storage Account for Azure Logic App queue and blob storage
Write-Host "`n"
Write-Host "Creating Azure Storage Account for Azure Logic App example"
Write-Host "`n"
$storageAccountName = "jumpstartappservices" + -join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object {[char]$_})

# Configuring and deploying sample Logic Apps template Azure dependencies
Write-Host "`n"
Write-Host "Configuring and deploying sample Logic App template Azure dependencies.`n"
Write-Host "Updating connectors-parameters.json with appropriate values.`n"
$connectorsParametersPath = "C:\Temp\ARM\connectors-parameters.json"
$spnObjectId = az ad sp show --id $Env:spnClientID --query objectId -o tsv
(Get-Content -Path $connectorsParametersPath) -replace '<azureLocation>',$Env:azureLocation | Set-Content -Path $connectorsParametersPath
(Get-Content -Path $connectorsParametersPath) -replace '<tenantId>',$Env:spnTenantId | Set-Content -Path $connectorsParametersPath
(Get-Content -Path $connectorsParametersPath) -replace '<objectId>',$spnObjectId | Set-Content -Path $connectorsParametersPath
(Get-Content -Path $connectorsParametersPath) -replace '<storageAccountName>',$storageAccountName | Set-Content -Path $connectorsParametersPath
az deployment group create --resource-group $Env:resourceGroup --template-file "C:\Temp\ARM\connectors-template.json" --parameters "C:\Temp\ARM\connectors-parameters.json"
$storageAccountKey = az storage account keys list --account-name $storageAccountName --query [0].value -o tsv
$blobConnectionRuntimeUrl = az resource show --resource-group $Env:resourceGroup -n azureblob --resource-type Microsoft.Web/connections --query properties.connectionRuntimeUrl -o tsv
$queueConnectionRuntimeUrl = az resource show --resource-group $Env:resourceGroup -n azurequeue --resource-type Microsoft.Web/connections --query properties.connectionRuntimeUrl -o tsv

# Creating the new Logic App in the Kubernetes environment 
Write-Host "Creating the new Azure Logic App application in the Kubernetes environment"
Write-Host "`n"
$customLocationId = $(az customlocation show --name "jumpstart-cl" --resource-group $Env:resourceGroup --query id -o tsv)
$logicAppName = "JumpstartLogicApp-" + -join ((48..57) + (97..122) | Get-Random -Count 5 | ForEach-Object {[char]$_})
az logicapp create --resource-group $Env:resourceGroup --name $logicAppName --custom-location $customLocationId --storage-account $storageAccountName
Do {
    Write-Host "Waiting for Azure Logic App to become available. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 15
    $buildService = $(if(kubectl get pods -n appservices | Select-String $logicAppName | Select-String "Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($buildService -eq "Nope")

Do {
    Write-Host "Waiting for log-processor to become available. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 15
    $logProcessorStatus = $(if(kubectl describe daemonset "arc-app-services-k8se-log-processor" -n appservices | Select-String "Pods Status:  3 Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($logProcessorStatus -eq "Nope")

# Deploy Logic App code
Write-Host "Packaging sample Logic App code and deploying to Azure Arc enabled Logic App.`n"
7z a c:\Temp\logicAppCode.zip c:\Temp\logicAppCode\*
az logicapp deployment source config-zip --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --src c:\Temp\logicAppCode.zip

# Configuring Logic App settings
Write-Host "Configuring Logic App settings.`n"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "resourceGroup=$Env:resourceGroup"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "subscriptionId=$Env:subscriptionId"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "location=$Env:azureLocation"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "spnClientId=$Env:spnClientId"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "spnTenantId=$Env:spnTenantId"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "spnClientSecret=$Env:spnClientSecret"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "storageAccountName=$storageAccountName"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "queueConnectionRuntimeUrl=$queueConnectionRuntimeUrl"
az logicapp config appsettings set --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId --settings "blobConnectionRuntimeUrl=$blobConnectionRuntimeUrl"

# Start Logic App
Write-Host "Starting Logic App"
Write-Host "`n"
# az logicapp start --name $logicAppName --resource-group $Env:resourceGroup --subscription $Env:subscriptionId

# Creating a While loop to generate 10 messages to storage queue
Write-Host "`n"
Write-Host "Creating a While loop to generate 10 messages to storage queue"
Write-Host "`n"
$i=1
Do {
    $messageString = "?name=Jumpstart"+$i
    az storage message put --content $messageString --queue-name "jumpstart-queue" --account-name $storageAccountName --account-key $storageAccountKey --auth-mode key
    $i++
    }
While ($i -le 10)

Write-Host "Finished deploying Logic App."
Write-Host "`n"
