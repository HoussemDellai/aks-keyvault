# src: https://github.com/Azure/kubernetes-keyvault-flexvol

# Deploy Key Vault FlexVolume to your existing AKS cluster with this command:
kubectl create -f https://raw.githubusercontent.com/Azure/kubernetes-keyvault-flexvol/master/deployment/kv-flexvol-installer.yaml
kubectl get pods -n kv

# Using Key Vault FlexVolume with Pod identity

# Install AAD Pod Identity on non-rbac cluster
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml

# Create an Azure Identity
az identity create -g aks-k8s-2020 -n aks-k8s-2020-identity -o json
# output
{
  "clientId": "179b59a2-a42e-47ad-9c3e-e8c42947fa7c",
  "clientSecretUrl": "https://control-westeurope.identity.azure.net/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/aks-k8s-2020/providers/Microsoft.ManagedIdentity/userAssignedIdentities/ak
s-k8s-2020-identity/credentials?tid=<YOUR_AZURE_TENANT_ID>&oid=7b4e9507-8857-43a6-b2bc-eb1
0997c4aea&aid=179b59a2-a42e-47ad-9c3e-e8c42947fa7c",
  "id": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/aks-k8s-2020/providers/Micro
soft.ManagedIdentity/userAssignedIdentities/aks-k8s-2020-identity",
  "location": "westeurope",
  "name": "aks-k8s-2020-identity",
  "principalId": "7b4e9507-8857-43a6-b2bc-eb10997c4aea",
  "resourceGroup": "aks-k8s-2020",
  "tags": {},
  "tenantId": "<YOUR_AZURE_TENANT_ID>",
  "type": "Microsoft.ManagedIdentity/userAssignedIdentities"
}

# Assign Cluster SPN Role 
# not needed

# Assign Azure Identity Roles
# Assign Reader Role to new Identity for your Key Vault
az role assignment create --role Reader --assignee "7b4e9507-8857-43a6-b2bc-eb10997c4aea" --scope /subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourceGroups/aks-k8s-2020/providers/Microsoft.KeyVault/vaults/keyvault-aks-2020

# set policy to access keys in your Key Vault
az keyvault set-policy -n "keyvault-aks-2020" --key-permissions get --spn "179b59a2-a42e-47ad-9c3e-e8c42947fa7c"
# set policy to access secrets in your Key Vault
az keyvault set-policy -n "keyvault-aks-2020" --secret-permissions get --spn "179b59a2-a42e-47ad-9c3e-e8c42947fa7c"
# set policy to access certs in your Key Vault
az keyvault set-policy -n "keyvault-aks-2020" --certificate-permissions get --spn "179b59a2-a42e-47ad-9c3e-e8c42947fa7c"


# Install the Azure Identity
kubectl apply -f aadpodidentity.yaml

# Install the Azure Identity Binding
kubectl apply -f aadpodidentitybinding.yaml

# Deploy your app
kubectl apply -f nginx-flex-kv-podidentity.yaml

# Validate the pod can access the secret from Key Vault
kubectl exec -it nginx-flex-kv-podid cat /kvmnt/DatabasePassword
@Aa123456
