# Quickstart: ArgoCD Web UI Setup and Azure Key Vault Secrets Migration

**Feature Branch**: `002-argocd-ui-akv-secrets`
**Estimated Setup Time**: 30-45 minutes

## Prerequisites

- [ ] Azure CLI installed and authenticated (`az login`)
- [ ] kubectl configured for AKS cluster
- [ ] Helm 3.x installed
- [ ] Access to Azure subscription with Key Vault creation permissions
- [ ] DNS configured for `argocd.ii-us.com` (or your domain)
- [ ] ArgoCD already installed in `argocd` namespace

## Quick Verification

Before starting, verify your environment:

```bash
# Check Azure CLI
az account show --query name -o tsv

# Check kubectl context
kubectl config current-context

# Verify ArgoCD namespace exists
kubectl get namespace argocd

# Verify cert-manager is installed
kubectl get pods -n cert-manager
```

## Step-by-Step Setup

### 1. Create Azure Key Vault (5 min)

```bash
# Set variables
export RESOURCE_GROUP="<your-aks-resource-group>"
export KEYVAULT_NAME="ii-n8n-secrets"
export LOCATION="eastus"

# Create Key Vault with RBAC authorization
az keyvault create \
  --name $KEYVAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-rbac-authorization true

# Store n8n encryption key (generate if not exists)
az keyvault secret set \
  --vault-name $KEYVAULT_NAME \
  --name "n8n-encryption-key" \
  --value "$(openssl rand -hex 32)"
```

### 2. Configure Workload Identity (10 min)

```bash
# Get AKS cluster info
export AKS_CLUSTER_NAME="<your-aks-cluster>"
export AKS_OIDC_ISSUER=$(az aks show \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Enable workload identity if not already enabled
az aks update \
  --name $AKS_CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --enable-workload-identity \
  --enable-oidc-issuer

# Create managed identity for ESO
az identity create \
  --name external-secrets-identity \
  --resource-group $RESOURCE_GROUP

# Get identity client ID
export IDENTITY_CLIENT_ID=$(az identity show \
  --name external-secrets-identity \
  --resource-group $RESOURCE_GROUP \
  --query clientId -o tsv)

# Assign Key Vault access
export KEYVAULT_ID=$(az keyvault show \
  --name $KEYVAULT_NAME \
  --query id -o tsv)

az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $IDENTITY_CLIENT_ID \
  --scope $KEYVAULT_ID

# Create federated credential
az identity federated-credential create \
  --name external-secrets-federated \
  --identity-name external-secrets-identity \
  --resource-group $RESOURCE_GROUP \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:external-secrets:external-secrets-sa"
```

### 3. Install External Secrets Operator (5 min)

```bash
# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true

# Wait for ESO to be ready
kubectl wait --for=condition=available deployment/external-secrets \
  -n external-secrets --timeout=120s
```

### 4. Create ESO ServiceAccount with Workload Identity (2 min)

```bash
# Create ServiceAccount for ESO
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: external-secrets
  annotations:
    azure.workload.identity/client-id: "$IDENTITY_CLIENT_ID"
  labels:
    azure.workload.identity/use: "true"
EOF
```

### 5. Create ClusterSecretStore (2 min)

```bash
# Create ClusterSecretStore
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "https://$KEYVAULT_NAME.vault.azure.net"
      serviceAccountRef:
        name: external-secrets-sa
        namespace: external-secrets
EOF

# Verify store is ready
kubectl get clustersecretstore azure-keyvault
```

### 6. Create ExternalSecret for n8n (2 min)

```bash
# Create ExternalSecret for n8n
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-secrets
  namespace: n8n-prod
spec:
  refreshInterval: 4h
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: n8n-secrets
    creationPolicy: Owner
  data:
    - secretKey: N8N_ENCRYPTION_KEY
      remoteRef:
        key: n8n-encryption-key
EOF

# Verify secret synced
kubectl get externalsecret n8n-secrets -n n8n-prod
kubectl get secret n8n-secrets -n n8n-prod
```

### 7. Configure ArgoCD Server for External Access (5 min)

```bash
# Patch ArgoCD server to run in insecure mode (TLS at ingress)
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

# Restart ArgoCD server to apply changes
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd
```

### 8. Create ArgoCD Ingress (3 min)

```bash
# Apply ArgoCD ingress
kubectl apply -f specs/002-argocd-ui-akv-secrets/contracts/argocd-ingress.yaml

# Wait for certificate to be issued
kubectl get certificate argocd-tls -n argocd --watch
```

### 9. Get ArgoCD Admin Password (2 min)

```bash
# Get initial admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# Optionally store in Key Vault
az keyvault secret set \
  --vault-name $KEYVAULT_NAME \
  --name "argocd-admin-password" \
  --value "$ARGOCD_PASSWORD"
```

## Verification

### Verify ArgoCD UI Access

1. Open browser to `https://argocd.ii-us.com`
2. Login with username `admin` and password from step 9
3. Verify you can see the n8n-prod application

### Verify Secret Sync

```bash
# Check ExternalSecret status
kubectl get externalsecret -A

# Verify synced secret has correct data
kubectl get secret n8n-secrets -n n8n-prod -o yaml

# Check n8n deployment uses the secret
kubectl get deployment n8n -n n8n-prod -o yaml | grep -A5 N8N_ENCRYPTION_KEY
```

### Test Secret Rotation

```bash
# Update secret in Key Vault
az keyvault secret set \
  --vault-name $KEYVAULT_NAME \
  --name "n8n-encryption-key" \
  --value "$(openssl rand -hex 32)"

# Force immediate sync (or wait for refreshInterval)
kubectl annotate es n8n-secrets -n n8n-prod \
  force-sync=$(date +%s) --overwrite

# Verify secret updated
kubectl get secret n8n-secrets -n n8n-prod \
  -o jsonpath="{.data.N8N_ENCRYPTION_KEY}" | base64 -d
```

## Troubleshooting

### ExternalSecret Not Syncing

```bash
# Check ESO controller logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets

# Check ExternalSecret status
kubectl describe externalsecret n8n-secrets -n n8n-prod
```

### Certificate Not Issued

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate status
kubectl describe certificate argocd-tls -n argocd

# Check certificate request
kubectl get certificaterequest -n argocd
```

### ArgoCD UI Not Accessible

```bash
# Check ingress status
kubectl describe ingress argocd-server -n argocd

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Verify server is running in insecure mode
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml
```

## Cleanup (if needed)

```bash
# Remove ExternalSecrets
kubectl delete externalsecret n8n-secrets -n n8n-prod

# Remove ArgoCD ingress
kubectl delete ingress argocd-server -n argocd

# Uninstall ESO
helm uninstall external-secrets -n external-secrets

# Delete managed identity
az identity delete --name external-secrets-identity --resource-group $RESOURCE_GROUP

# Delete Key Vault (careful - this deletes all secrets!)
# az keyvault delete --name $KEYVAULT_NAME
```

## Next Steps

1. Remove plain-text secrets from `k8s/secrets/n8n-secrets.yaml`
2. Update kustomization.yaml to include ExternalSecret resources
3. Configure ArgoCD to manage the ExternalSecret resources via GitOps
4. Set up monitoring/alerting for secret sync failures
5. Document secret rotation procedures
