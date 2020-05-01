echo "Setting up the variables..."
$subscriptionId = (az account show | ConvertFrom-Json).id
$tenantId = (az account show | ConvertFrom-Json).tenantId
$location = "westeurope"
$resourceGroupName = "rg-demo08"
$aksName = "aks-demo08"
$keyVaultName = "keyvault-demo08"
$secret1Name = "DatabaseLogin"
$secret2Name = "DatabasePassword"
$secret1Alias = "DATABASE_LOGIN"
$secret2Alias = "DATABASE_PASSWORD" 
$identityName = "identity-aks-kv"
$identitySelector = "azure-kv"
$secretProviderClassName = "secret-provider-kv"

# echo "Creating Resource Group..."
# $rg = az group create -n $resourceGroupName -l $location | ConvertFrom-Json

# echo "Creating AKS cluster..." # doesn't work with AKS with Managed Identity!
# $aks = az aks create -n $aksName -g $resourceGroupName --enable-managed-identity --kubernetes-version 1.17.3 --node-count 1 | ConvertFrom-Json
$aks = (az aks show -n $aksName -g $resourceGroupName | ConvertFrom-Json) # retrieve existing AKS

# echo "Connecting/athenticating to AKS..."
az aks get-credentials -n $aksName -g $resourceGroupName

echo "Creating Key Vault..."
$keyVault = az keyvault create -n $keyVaultName -g $resourceGroupName -l $location --enable-soft-delete true --retention-days 7 | ConvertFrom-Json
# $keyVault = (az keyvault show -n $keyVaultName | ConvertFrom-Json) # retrieve existing KV

echo "Creating Secrets in Key Vault..."
az keyvault secret set --name $secret1Name --value "Houssem" --vault-name $keyVaultName
az keyvault secret set --name $secret2Name --value "P@ssword123456" --vault-name $keyVaultName

echo "Adding Helm repo for Secret Store CSI..."
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts

echo "Installing Secrets Store CSI Driver using Helm..."
kubectl create ns csi-driver
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --namespace csi-driver
kubectl get pods --namespace=csi-driver

echo "Installing Secrets Store CSI Driver with Azure Key Vault Provider..."
kubectl apply -f https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/deployment/provider-azure-installer.yaml --namespace csi-driver
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

echo "Installing AAD Pod Identity into AKS..."
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
kubectl get pods

echo "Creating an Azure Identity..."
$identity = az identity create -g $resourceGroupName -n $identityName | ConvertFrom-Json

echo "Assigning Reader Role to new Identity for Key Vault..."
az role assignment create --role "Reader" --assignee $identity.principalId --scope $keyVault.id

echo "Providing required permissions for MIC..."
az role assignment create --role "Managed Identity Operator" --assignee $aks.servicePrincipalProfile.clientId --scope $identity.id

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

echo "Validating the pod has access to the secrets from Key Vault..."
kubectl exec -it nginx-secrets-store ls /mnt/secrets-store/
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/DATABASE_LOGIN
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/$secret1Alias
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/DATABASE_PASSWORD
kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/$secret2Alias
 