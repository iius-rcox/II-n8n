# Azure Infrastructure Setup for External Secrets Operator

This document provides step-by-step instructions for setting up Azure Key Vault and Workload Identity for the External Secrets Operator integration.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- kubectl configured for your AKS cluster
- Helm 3.x installed
- Appropriate Azure RBAC permissions (Contributor or higher on resource group)

## Environment Variables

Set these variables before running the commands:

```bash
# Required - Update these with your actual values
export RESOURCE_GROUP="<your-aks-resource-group>"
export AKS_CLUSTER_NAME="<your-aks-cluster-name>"
export LOCATION="eastus"
export KEYVAULT_NAME="ii-n8n-secrets"

# These will be populated by commands
export IDENTITY_NAME="external-secrets-identity"
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## Step 1: Create Azure Key Vault (T001)

Create a Key Vault with RBAC authorization enabled:

```bash
az keyvault create \
  --name $KEYVAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-rbac-authorization true \
  --enable-soft-delete true \
  --retention-days 90
```

Verify creation:

```bash
az keyvault show --name $KEYVAULT_NAME --query "{name:name,location:location,rbacEnabled:properties.enableRbacAuthorization}"
```

## Step 2: Create Managed Identity for ESO (T002)

Create a user-assigned managed identity:

```bash
az identity create \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

Get the identity details:

```bash
export IDENTITY_CLIENT_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query clientId -o tsv)

export IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)

echo "Client ID: $IDENTITY_CLIENT_ID"
echo "Principal ID: $IDENTITY_PRINCIPAL_ID"
```

## Step 3: Enable Workload Identity on AKS (T003)

Enable Workload Identity and OIDC issuer on your AKS cluster:

```bash
az aks update \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --enable-workload-identity \
  --enable-oidc-issuer
```

Get the OIDC issuer URL:

```bash
export AKS_OIDC_ISSUER=$(az aks show \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

echo "OIDC Issuer: $AKS_OIDC_ISSUER"
```

## Step 4: Assign Key Vault Secrets User Role (T004)

Grant the managed identity permission to read secrets:

```bash
export KEYVAULT_ID=$(az keyvault show \
  --name $KEYVAULT_NAME \
  --query id -o tsv)

az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id $IDENTITY_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal \
  --scope $KEYVAULT_ID
```

Verify the role assignment:

```bash
az role assignment list \
  --scope $KEYVAULT_ID \
  --query "[?principalId=='$IDENTITY_PRINCIPAL_ID'].{role:roleDefinitionName,scope:scope}" \
  -o table
```

## Step 5: Create Federated Credential (T005)

Link the Kubernetes ServiceAccount to the Azure Managed Identity:

```bash
az identity federated-credential create \
  --name "external-secrets-federated" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:external-secrets:external-secrets-sa" \
  --audiences "api://AzureADTokenExchange"
```

Verify the federated credential:

```bash
az identity federated-credential show \
  --name "external-secrets-federated" \
  --identity-name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP
```

## Step 6: Store Secrets in Key Vault (T006)

Store the n8n encryption key:

```bash
# Generate a secure encryption key if you don't have one
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Store in Key Vault
az keyvault secret set \
  --vault-name $KEYVAULT_NAME \
  --name "n8n-encryption-key" \
  --value "$N8N_ENCRYPTION_KEY"
```

Verify the secret was stored:

```bash
az keyvault secret show \
  --vault-name $KEYVAULT_NAME \
  --name "n8n-encryption-key" \
  --query "{name:name,enabled:attributes.enabled,created:attributes.created}"
```

## Output Summary

After completing all steps, you should have:

| Resource | Name | Purpose |
|----------|------|---------|
| Key Vault | `ii-n8n-secrets` | Secure secret storage |
| Managed Identity | `external-secrets-identity` | ESO authentication |
| Federated Credential | `external-secrets-federated` | K8s SA to Azure identity link |
| Secret | `n8n-encryption-key` | n8n data encryption |

Save these values for the Kubernetes configuration:

```bash
echo "=== Values for Kubernetes Configuration ==="
echo "KEYVAULT_NAME: $KEYVAULT_NAME"
echo "KEYVAULT_URL: https://$KEYVAULT_NAME.vault.azure.net"
echo "IDENTITY_CLIENT_ID: $IDENTITY_CLIENT_ID"
echo "AKS_OIDC_ISSUER: $AKS_OIDC_ISSUER"
```

## Next Steps

1. Install External Secrets Operator (see Phase 2 in tasks.md)
2. Create ServiceAccount with Workload Identity annotation
3. Create ClusterSecretStore connecting to Key Vault
4. Create ExternalSecret resources for n8n and ArgoCD

## Troubleshooting

### Identity Not Authorized

If you see "Caller is not authorized" errors:

```bash
# Verify role assignment
az role assignment list --scope $KEYVAULT_ID --query "[].{role:roleDefinitionName,principal:principalName}" -o table

# Check identity can access Key Vault
az keyvault secret list --vault-name $KEYVAULT_NAME --query "[].name" -o tsv
```

### Federated Credential Issues

If workload identity isn't working:

```bash
# Verify OIDC issuer is enabled
az aks show --name $AKS_CLUSTER_NAME --resource-group $RESOURCE_GROUP --query "oidcIssuerProfile"

# Check federated credential subject matches ServiceAccount
az identity federated-credential list --identity-name $IDENTITY_NAME --resource-group $RESOURCE_GROUP
```

### Secret Not Syncing

Check External Secrets Operator logs:

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```
