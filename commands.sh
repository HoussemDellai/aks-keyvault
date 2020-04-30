# src: https://github.com/Azure/secrets-store-csi-driver-provider-azure

# 0. Preparation 
# Create AKS cluster.
# Create Azure Key Vault with Secrets:
#    DatabaseLogin: Houssem
#    DatabasePassword: MyP@ssword123456

# Steps from: https://github.com/kubernetes-sigs/secrets-store-csi-driver#usage
# 1. Installing Secrets Store CSI Driver and Key Vault Provider
# 1.1. Adding Helm repo
 $ helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
 $ kubectl create ns csi-driver

# 1.2. Installing Secrets Store CSI Driver using Helm
 $ helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --namespace csi-driver
 $ kubectl get pods -n csi-driver

# 1.3. Installing Secrets Store CSI Driver with Azure Key Vault Provider
 $ kubectl apply -f https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/deployment/provider-azure-installer.yaml --namespace csi-driver
# You should see the provider pods running on each agent node:
 $ kubectl get pods -n csi-driver

# 2. Using the Azure Key Vault Provider
# Now that we have the driver installed, let's use the SecretProviderClass to configure
# the Key Vault instance to connect to, what keys, secrets or certificates to retrieve.
# Create the SecretProviderClass for Azure Key Vault 
 $ kubectl create -f secret-provider-class-kv.yaml

# Note: Hashicorp Vault is also supported.

# 3. Installing Pod Identity and providing access to Key Vault

# The Azure Key Vault Provider offers four modes for accessing a Key Vault instance:
#   Service Principal
#   Pod Identity
#   VMSS User Assigned Managed Identity
#   VMSS System Assigned Managed Identity
# Here we'll be using Pod Identity.

# 3.1. Installing AAD Pod Identity into AKS
# The cluster here have RBAC enabled
 $ kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
 $ kubectl get pods

# 3.2. Creating Azure User Identity
# Create an Azure User Identity with the following command. Get clientId and id from the output.
 $ az identity create -g rg-demo -n identity-aks-kv

# 3.3. # Assigning Reader Role to new Identity for your keyvault
 $ az role assignment create --role Reader --assignee "f8bb59bd-b704-4274-8391-3b0791d7a02c" --scope /subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.KeyVault/vaults/az-key-vault-demo

# 3.4. Providing required permissions for MIC
# Assign "Managed Identity Operator" role to new Identity for your AKS.
# $ az aks show -g <resource group> -n <ask cluster name> --query servicePrincipalProfile.clientId -o tsv
 $ az aks show -g rg-demo -n aks-demo --query servicePrincipalProfile

 $ az role assignment create --role "Managed Identity Operator" --assignee "da570956-eea4-474a-a0ee-fac9098bf1cf" --scope /subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity-aks-kv

# 3.5. Setting policy to access secrets in Key Vault
 $ az keyvault set-policy -n  az-key-vault-demo --secret-permissions get --spn "a0c038fd-3df3-4eaf-bb34-abdd4f78a0db"

# To set policy to access keys in your keyvault
# az keyvault set-policy -n $KV_NAME --key-permissions get --spn <YOUR AZURE USER IDENTITY CLIENT ID>
# To set policy to access certs in your keyvault
# az keyvault set-policy -n $KV_NAME --certificate-permissions get --spn <YOUR AZURE USER IDENTITY CLIENT ID>

# 4. Adding AzureIdentity and AzureIdentityBinding
# 4.1 Adding a new AzureIdentity for the new identity to your cluster
# Edit and save this as aadpodidentity.yaml
# Set type: 0 for Managed Service Identity; type: 1 for Service Principal In this case, we are using managed service identity, type: 0. Create a new name for the AzureIdentity. Set resourceID to id of the Azure User Identity created from the previous step.
 $ kubectl create -f aadpodidentity.yaml

# 4.2. Adding a new AzureIdentityBinding for the new Azure identity to your cluster
# Edit and save this as aadpodidentitybinding.yaml
 $ kubectl create -f aadpodidentitybinding.yaml

# 5. Accessing Key Vault secrets from a Pod in AKS
# 5.1. Deplloying an Nginx Pod for testing
 $ kubectl create -f nginx-secrets-pod.yaml

# 5.2. Validating the pod has access to the secrets from key vault:
 $ kubectl exec -it nginx-secrets-store ls /mnt/secrets-store/
DATABASE_LOGIN  DATABASE_PASSWORD
 $ kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/DATABASE_PASSWORD
MyP@ssword123456