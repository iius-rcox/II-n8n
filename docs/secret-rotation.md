# Secret Rotation Procedures

This document describes how to rotate secrets managed by External Secrets Operator with Azure Key Vault.

## Overview

Secrets are automatically synced from Azure Key Vault to Kubernetes every 4 hours (configurable via `refreshInterval` in ExternalSecret resources). For immediate rotation, follow the manual procedures below.

## Automatic Rotation

External Secrets Operator automatically syncs secrets from Azure Key Vault at the configured refresh interval:

| Secret | ExternalSecret | Refresh Interval | Namespace |
|--------|---------------|------------------|-----------|
| n8n-encryption-key | n8n-secrets | 4h | n8n-prod |
| argocd-admin-password | argocd-admin-secret | 4h | argocd |

To change the refresh interval, edit the ExternalSecret resource:

```bash
kubectl edit externalsecret n8n-secrets -n n8n-prod
# Change spec.refreshInterval to desired value (e.g., 1h, 30m)
```

## Manual Secret Rotation

### Step 1: Update Secret in Azure Key Vault

```bash
# Set environment variables
export KEYVAULT_NAME="ii-n8n-secrets"

# For n8n encryption key
az keyvault secret set \
  --vault-name $KEYVAULT_NAME \
  --name "n8n-encryption-key" \
  --value "$(openssl rand -hex 32)"

# For ArgoCD admin password (bcrypt hashed)
NEW_PASSWORD="your-new-secure-password"
HASHED_PASSWORD=$(htpasswd -nbBC 10 "" "$NEW_PASSWORD" | tr -d ':\n' | sed 's/$2y/$2a/')
az keyvault secret set \
  --vault-name $KEYVAULT_NAME \
  --name "argocd-admin-password" \
  --value "$HASHED_PASSWORD"
```

### Step 2: Force Immediate Sync

Trigger an immediate sync without waiting for the refresh interval:

```bash
# For n8n secrets
kubectl annotate externalsecret n8n-secrets -n n8n-prod \
  force-sync=$(date +%s) --overwrite

# For ArgoCD secrets
kubectl annotate externalsecret argocd-admin-secret -n argocd \
  force-sync=$(date +%s) --overwrite
```

### Step 3: Verify Sync Status

```bash
# Check ExternalSecret status
kubectl get externalsecret n8n-secrets -n n8n-prod
kubectl get externalsecret argocd-admin-secret -n argocd

# View detailed status
kubectl describe externalsecret n8n-secrets -n n8n-prod

# Verify the Kubernetes secret was updated
kubectl get secret n8n-secrets -n n8n-prod -o jsonpath='{.metadata.resourceVersion}'
```

### Step 4: Restart Applications (if needed)

Most applications read secrets at startup. If your application doesn't support hot-reloading secrets, restart the deployment:

```bash
# Restart n8n deployment
kubectl rollout restart deployment/n8n -n n8n-prod

# Watch rollout status
kubectl rollout status deployment/n8n -n n8n-prod
```

**Note**: ArgoCD reads the admin password from the secret dynamically, so no restart is typically needed.

## Monitoring Secret Sync

### Check ExternalSecret Health

```bash
# List all ExternalSecrets and their status
kubectl get externalsecret -A

# Check for sync errors
kubectl get externalsecret -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
```

### View External Secrets Operator Logs

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100
```

### Check Azure Key Vault Access

```bash
# Verify secrets exist in Key Vault
az keyvault secret list --vault-name $KEYVAULT_NAME --query "[].name" -o tsv

# Check secret versions
az keyvault secret list-versions --vault-name $KEYVAULT_NAME --name "n8n-encryption-key" --query "[].{id:id,created:attributes.created,enabled:attributes.enabled}" -o table
```

## Troubleshooting

### Secret Not Syncing

1. **Check ExternalSecret status**:
   ```bash
   kubectl describe externalsecret <name> -n <namespace>
   ```

2. **Verify ClusterSecretStore is Ready**:
   ```bash
   kubectl get clustersecretstore azure-keyvault
   kubectl describe clustersecretstore azure-keyvault
   ```

3. **Check ESO controller logs**:
   ```bash
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
   ```

4. **Verify Azure permissions**:
   ```bash
   # Check role assignment
   az role assignment list --scope $(az keyvault show --name $KEYVAULT_NAME --query id -o tsv) --query "[].{role:roleDefinitionName,principal:principalName}" -o table
   ```

### Authentication Errors

1. **Verify Workload Identity configuration**:
   ```bash
   # Check ServiceAccount annotations
   kubectl get sa external-secrets-sa -n external-secrets -o yaml

   # Check federated credential
   az identity federated-credential list --identity-name external-secrets-identity --resource-group <rg>
   ```

2. **Test Key Vault access manually**:
   ```bash
   # From a pod with the ServiceAccount
   az keyvault secret show --vault-name $KEYVAULT_NAME --name "n8n-encryption-key"
   ```

## Security Best Practices

1. **Rotate secrets regularly** - At minimum every 90 days for production
2. **Use strong passwords** - At least 32 characters for encryption keys
3. **Enable Key Vault audit logging** - Monitor who accesses secrets
4. **Limit refresh intervals** - Balance security with API costs (4h recommended)
5. **Monitor sync failures** - Set up alerts for ExternalSecret sync failures

## Related Documentation

- [Azure Setup](azure-setup.md) - Initial Key Vault and identity configuration
- [External Secrets Operator](https://external-secrets.io/latest/provider/azure-key-vault/) - Official ESO docs
- [Azure Key Vault Best Practices](https://learn.microsoft.com/en-us/azure/key-vault/general/best-practices)
