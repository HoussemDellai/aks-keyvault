# src: https://github.com/Azure/secrets-store-csi-driver-provider-azure

# 0. Preparation 
# Create AKS cluster.
# Create Azure Key Vault with Secrets:
#    DatabaseLogin: Houssem
#    DatabasePassword: MyP@ssword123456

# Steps from: https://github.com/kubernetes-sigs/secrets-store-csi-driver#usage
# 1. Install the Secrets Store CSI Driver
# 1.1. Add Helm repo
helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
 $ kubectl create ns csi-driver
namespace/csi-driver created
# 1.2. Install Secrets Store CSI Driver using Helm
 $ helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --namespace csi-driver
NAME: csi-secrets-store
LAST DEPLOYED: Wed Apr 29 14:54:22 2020
REVISION: 1
TEST SUITE: None
NOTES:
The Secrets Store CSI Driver is getting deployed to your cluster.

To verify that Secrets Store CSI Driver has started, run:

 $ kubectl  get pods --namespace=csi-driver

Now you can follow these steps https://github.com/kubernetes-sigs/secrets-store-csi-driver#use-the-secrets-store-csi-driver
to create a SecretProviderClass resource, and a deployment using the SecretProviderClass.

 $ kubectl get pods -n csi-driver
NAME                                               READY   STATUS    RESTARTS   AGE
csi-secrets-store-secrets-store-csi-driver-9mgrl   3/3     Running   0          2m13s

# 1.3. Install the Secrets Store CSI Driver with Azure Key Vault Provider
# [REQUIRED FOR AZURE PROVIDER]
 $ kubectl apply -f https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/deployment/provider-azure-installer.yaml --namespace csi-driver
daemonset.apps/csi-secrets-store-provider-azure created
# You should see the provider pods running on each agent node:
 $ kubectl get pods -n csi-driver
NAME                                               READY   STATUS    RESTARTS   AGE
csi-secrets-store-provider-azure-mdl72             1/1     Running   0          70s
csi-secrets-store-secrets-store-csi-driver-9mgrl   3/3     Running   0          8m25s

# 2. Using the Azure Key Vault Provider
# Now that we have the driver installed, let's use the SecretProviderClass to configure
# the Key Vault instance to connect to, what keys, secrets or certificates to retrieve.
# Create the SecretProviderClass for Azure Key Vault 
 $ kubectl create -f secret-provider-class-kv.yaml
secretproviderclass.secrets-store.csi.x-k8s.io/secret-provider-kv created
# Note: Hashicorp Vault is also supported.

# 3. Provide Identity to Access Key Vault using Pod Identity

# The Azure Key Vault Provider offers four modes for accessing a Key Vault instance:
#   Service Principal
#   Pod Identity
#   VMSS User Assigned Managed Identity
#   VMSS System Assigned Managed Identity
# Here we'll be using Pod Identity.

# 3.1. Install the aad-pod-identity components to your cluster
The cluster here have RBAC enabled
 $ kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
serviceaccount/aad-pod-id-nmi-service-account created
customresourcedefinition.apiextensions.k8s.io/azureassignedidentities.aadpodidentity.k8s.io created
customresourcedefinition.apiextensions.k8s.io/azureidentitybindings.aadpodidentity.k8s.io created
customresourcedefinition.apiextensions.k8s.io/azureidentities.aadpodidentity.k8s.io created
customresourcedefinition.apiextensions.k8s.io/azurepodidentityexceptions.aadpodidentity.k8s.io created
clusterrole.rbac.authorization.k8s.io/aad-pod-id-nmi-role created
clusterrolebinding.rbac.authorization.k8s.io/aad-pod-id-nmi-binding created
daemonset.apps/nmi created
serviceaccount/aad-pod-id-mic-service-account created
clusterrole.rbac.authorization.k8s.io/aad-pod-id-mic-role created
clusterrolebinding.rbac.authorization.k8s.io/aad-pod-id-mic-binding created
deployment.apps/mic created
 $ kubectl get pods
NAME                   READY   STATUS    RESTARTS   AGE
mic-76dd75ddf9-59vgm   1/1     Running   0          6s
mic-76dd75ddf9-qrvr4   1/1     Running   0          6s
nmi-64gfh              1/1     Running   0          7s

# 3.2. Create an Azure User Identity
# Create an Azure User Identity with the following command. Get clientId and id from the output.
 $ az identity create -g rg-demo -n identity-aks-kv
{
  "clientId": "a0c038fd-3df3-4eaf-bb34-abdd4f78a0db",
  "clientSecretUrl": "https://control-westeurope.identity.azure.net/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity-aks-kv/credentials?tid=<YOUR_AZURE_TENANT_ID>&oid=f8bb59bd-b704-4274-8391-3b0791d7a02c&aid=a0c038fd-3df3-4eaf",
  "id": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity-aks-kv",
  "location": "westeurope",
  "name": "identity-aks-kv",
  "principalId": "f8bb59bd-b704-4274-8391-3b0791d7a02c",
  "resourceGroup": "rg-demo",
  "tags": {},
  "tenantId": "<YOUR_AZURE_TENANT_ID>",
  "type": "Microsoft.ManagedIdentity/userAssignedIdentities"
}

# 3.3. # Assign Reader Role to new Identity for your keyvault
 $ az role assignment create --role Reader --assignee "f8bb59bd-b704-4274-8391-3b0791d7a02c" --scope /subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.KeyVault/vaults/az-key-vault-demo
{
  "canDelegate": null,
  "id": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.KeyVault/vaults/az-key-vault-demo/providers/Microsoft.Authorization/roleAssignments/d6bd00b8-9734-4c53-9de3-5a5b203c3286",
  "name": "d6bd00b8-9734-4c53-9de3-5a5b203c3286",
  "principalId": "f8bb59bd-b704-4274-8391-3b0791d7a02c",
  "principalType": "ServicePrincipal",
  "resourceGroup": "rg-demo",
  "roleDefinitionId": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7",
  "scope": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.KeyVault/vaults/az-key-vault-demo",
  "type": "Microsoft.Authorization/roleAssignments"
}

# 3.4. Providing required permissions for MIC
# Assign "Managed Identity Operator" role to new Identity for your AKS.
# $ az aks show -g <resource group> -n <ask cluster name> --query servicePrincipalProfile.clientId -o tsv
 $ az aks show -g rg-demo -n aks-demo --query servicePrincipalProfile
{
  "clientId": "da570956-eea4-474a-a0ee-fac9098bf1cf"
}

 $ az role assignment create --role "Managed Identity Operator" --assignee "da570956-eea4-474a-a0ee-fac9098bf1cf" --scope /subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity-aks-kv
{
  "canDelegate": null,
  "id": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity-aks-kv/providers/Microsoft.Authorization/roleAssignments/c018c932-c06b-446c-863e-bc85c687cf69",
  "name": "c018c932-c06b-446c-863e-bc85c687cf69",
  "principalId": "2736b5eb-e79e-48fa-9348-19f9c64ce7b3",
  "principalType": "ServicePrincipal",
  "resourceGroup": "rg-demo",
  "roleDefinitionId": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/providers/Microsoft.Authorization/roleDefinitions/f1a07417-d97a-45cb-824c-7a7467783830",
  "scope": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourcegroups/rg-demo/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity-aks-kv",
  "type": "Microsoft.Authorization/roleAssignments"
}

# 3.5. Set policy to access secrets in your keyvault
 $ az keyvault set-policy -n  az-key-vault-demo --secret-permissions get --spn "a0c038fd-3df3-4eaf-bb34-abdd4f78a0db"
{
  "id": "/subscriptions/<YOUR_AZURE_SUBSCRIPTION_ID>/resourceGroups/rg-demo/providers/Microsoft.KeyVault/vaults/az-key-vault-demo",
  "location": "westeurope",
  "name": "az-key-vault-demo",
  "properties": {
    "accessPolicies": [
      { removed-for-brievety }
      {
        "applicationId": null,
        "objectId": "f8bb59bd-b704-4274-8391-3b0791d7a02c",
        "permissions": {
          "certificates": null,
          "keys": null,
          "secrets": [
            "get"
          ],
          "storage": null
        },
        "tenantId": "<YOUR_AZURE_TENANT_ID>"
      }
    ]
}

# To set policy to access keys in your keyvault
# az keyvault set-policy -n $KV_NAME --key-permissions get --spn <YOUR AZURE USER IDENTITY CLIENT ID>
# To set policy to access certs in your keyvault
# az keyvault set-policy -n $KV_NAME --certificate-permissions get --spn <YOUR AZURE USER IDENTITY CLIENT ID>

# 4. Add AzureIdentity and AzureIdentityBinding
# 4.1 Add a new AzureIdentity for the new identity to your cluster
# Edit and save this as aadpodidentity.yaml
# Set type: 0 for Managed Service Identity; type: 1 for Service Principal In this case, we are using managed service identity, type: 0. Create a new name for the AzureIdentity. Set resourceID to id of the Azure User Identity created from the previous step.
 $ kubectl create -f aadpodidentity.yaml
azureidentity.aadpodidentity.k8s.io/azure-identity-kv created

# 4.2. Add a new AzureIdentityBinding for the new Azure identity to your cluster
# Edit and save this as aadpodidentitybinding.yaml
 $ kubectl create -f aadpodidentitybinding.yaml
azureidentitybinding.aadpodidentity.k8s.io/azure-identity-binding-kv created

# 5. Access Key Vault secrets from a Pod in AKS
# 5.1. Deplloy an Nginx Pod for testing
 $ kubectl create -f nginx-secrets-pod.yaml
pod/nginx-secrets-store created

# 5.2. Validate the pod has access to the secrets from key vault:
 $ kubectl exec -it nginx-secrets-store ls /mnt/secrets-store/
DATABASE_LOGIN  DATABASE_PASSWORD
 $ kubectl exec -it nginx-secrets-store cat /mnt/secrets-store/DATABASE_PASSWORD
MyP@ssword123456