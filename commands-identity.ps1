echo "Setting up the variables..."
$suffix = "demo03"
$subscriptionId = (az account show | ConvertFrom-Json).id
$tenantId = (az account show | ConvertFrom-Json).tenantId
$location = "westeurope"
$resourceGroupName = "rg-" + $suffix
$aksName = "aks-" + $suffix
$keyVaultName = "keyvaultaks" + $suffix
$secret1Name = "DatabaseLogin"
$secret2Name = "DatabasePassword"
$secret1Alias = "DATABASE_LOGIN"
$secret2Alias = "DATABASE_PASSWORD" 
$identityName = "identity-aks-kv"
$identitySelector = "azure-kv"
$secretProviderClassName = "secret-provider-kv"
$acrName = "acrforaks" + $suffix
$isAKSWithManagedIdentity = "true"

# echo "Creating Resource Group..."
$resourceGroup = az group create -n $resourceGroupName -l $location | ConvertFrom-Json

# echo "Createing ACR..."
$acr = az acr create --resource-group $resourceGroupName --name $acrName --sku Basic | ConvertFrom-Json
az acr login -n $acrName --expose-token

If ($isAKSWithManagedIdentity -eq "true") {
echo "Creating AKS cluster with Managed Identity..."
$aks = az aks create -n $aksName -g $resourceGroupName --kubernetes-version 1.17.3 --node-count 1 --attach-acr $acrName  --enable-managed-identity | ConvertFrom-Json
} Else {
echo "Creating AKS cluster with Service Principal..."
$aks = az aks create -n $aksName -g $resourceGroupName --kubernetes-version 1.17.3 --node-count 1 --attach-acr $acrName | ConvertFrom-Json
}
# retrieve existing AKS
$aks = (az aks show -n $aksName -g $resourceGroupName | ConvertFrom-Json)

# echo "Connecting/athenticating to AKS..."
az aks get-credentials -n $aksName -g $resourceGroupName

echo "Creating Key Vault..."
$keyVault = az keyvault create -n $keyVaultName -g $resourceGroupName -l $location --enable-soft-delete true --retention-days 7 | ConvertFrom-Json
# $keyVault = az keyvault show -n $keyVaultName | ConvertFrom-Json # retrieve existing KV

echo "Creating Secrets in Key Vault..."
az keyvault secret set --name $secret1Name --value "Houssem" --vault-name $keyVaultName
az keyvault secret set --name $secret2Name --value "P@ssword123456" --vault-name $keyVaultName

# echo "Installing Secrets Store CSI Driver using Helm..."
kubectl create ns csi-driver
echo "Installing Secrets Store CSI Driver with Azure Key Vault Provider..."
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
helm install csi-azure csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --namespace csi-driver
sleep 2
kubectl get pods -n csi-driver

echo "Using the Azure Key Vault Provider..."
$secretProviderKV = @"
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: $($secretProviderClassName)
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"
    useVMManagedIdentity: "false"
    userAssignedIdentityID: ""
    keyvaultName: $keyVaultName
    cloudName: AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: $secret1Name
          objectAlias: $secret1Alias
          objectType: secret
          objectVersion: ""
        - |
          objectName: $secret2Name
          objectAlias: $secret2Alias
          objectType: secret
          objectVersion: ""
    resourceGroup: $resourceGroupName
    subscriptionId: $subscriptionId
    tenantId: $tenantId
"@
$secretProviderKV | kubectl create -f -

# Run the following 2 commands only if using AKS with Managed Identity
If ($isAKSWithManagedIdentity -eq "true") {
az role assignment create --role "Managed Identity Operator" --assignee $aks.identityProfile.kubeletidentity.clientId --scope /subscriptions/$subscriptionId/resourcegroups/$($aks.nodeResourceGroup)
az role assignment create --role "Virtual Machine Contributor" --assignee $aks.identityProfile.kubeletidentity.clientId --scope /subscriptions/$subscriptionId/resourcegroups/$($aks.nodeResourceGroup)
# If user-assigned identities that are not within the cluster resource group
# az role assignment create --role "Managed Identity Operator" --assignee $aks.identityProfile.kubeletidentity.clientId --scope /subscriptions/$subscriptionId/resourcegroups/$resourceGroupName
}

echo "Installing AAD Pod Identity into AKS..."
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
kubectl get pods

# If using AKS with Managed Identity, retrieve the existing Identity
If ($isAKSWithManagedIdentity -eq "true") {
echo "Retrieving the existing Azure Identity..."
$existingIdentity = az resource list -g $aks.nodeResourceGroup --query "[?contains(type, 'Microsoft.ManagedIdentity/userAssignedIdentities')]"  | ConvertFrom-Json
$identity = az identity show -n $existingIdentity.name -g $existingIdentity.resourceGroup | ConvertFrom-Json
} Else {
# If using AKS with Service Principal, create new Identity
echo "Creating an Azure Identity..."
$identity = az identity create -g $resourceGroupName -n $identityName | ConvertFrom-Json
}

echo "Assigning Reader Role to new Identity for Key Vault..."
az role assignment create --role "Reader" --assignee $identity.principalId --scope $keyVault.id

# Run the following command only if using AKS with Service Principal
If ($isAKSWithManagedIdentity -eq "false") {
echo "Providing required permissions for MIC..."
az role assignment create --role "Managed Identity Operator" --assignee $aks.servicePrincipalProfile.clientId --scope $identity.id
}

echo "Setting policy to access secrets in Key Vault..."
az keyvault set-policy -n $keyVaultName --secret-permissions get --spn $identity.clientId

echo "Adding AzureIdentity and AzureIdentityBinding..."
$aadPodIdentityAndBinding = @"
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: $($identityName)
spec:
  type: 0
  resourceID: $($identity.id)
  clientID: $($identity.clientId)
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: $($identityName)-binding
spec:
  azureIdentity: $($identityName)
  selector: $($identitySelector)
"@
$aadPodIdentityAndBinding | kubectl apply -f -

echo "Deploying a Nginx Pod for testing..."
$nginxPod = @"
kind: Pod
apiVersion: v1
metadata:
  name: nginx-secrets-store
  labels:
    aadpodidbinding: $($identitySelector)
spec:
  containers:
    - name: nginx
      image: nginx
      volumeMounts:
      - name: secrets-store-inline
        mountPath: "/mnt/secrets-store"
        readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: $($secretProviderClassName)
"@
$nginxPod | kubectl apply -f -

sleep 10
kubectl get pods

echo "Validating the pod has access to the secrets from Key Vault..."
kubectl exec -it nginx-secrets-store ls /mnt/secrets-store/
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/DATABASE_LOGIN
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/$secret1Alias
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/DATABASE_PASSWORD
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/$secret2Alias

# Testing ACR and AKS authN
# az acr build -t productsstore:0.1 -r $acrName .\ProductsStoreOnKubernetes\MvcApp\
# kubectl run --image=$acrName.azurecr.io/productsstore:0.1 prodstore --generator=run-pod/v1

# clean up resources 
# az group delete --no-wait -n $resourceGroupName
# az group delete --no-wait -n $aks.nodeResourceGroup