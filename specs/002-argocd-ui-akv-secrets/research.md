# Research: ArgoCD Web UI Setup and Azure Key Vault Secrets Migration

**Date**: 2025-12-16
**Feature Branch**: `002-argocd-ui-akv-secrets`

## Research Topics

### 1. External Secrets Operator vs Azure Key Vault CSI Driver

**Decision**: Use External Secrets Operator (ESO)

**Rationale**:
- Perfect fit for ArgoCD declarative GitOps - entire secret configuration lives in Git, version-controlled and auditable
- Creates and maintains Kubernetes Secrets independently of pod lifecycle (secrets persist even when pods are deleted)
- Superior secret rotation without pod restarts (configurable refresh intervals)
- Better integration with ArgoCD's declarative model
- Multi-provider support if future cloud migration needed

**Alternatives Considered**:

| Option | Pros | Cons | Why Rejected |
|--------|------|------|--------------|
| Azure Key Vault CSI Driver | Microsoft native, AKS add-on, secrets never in etcd | Secrets only available after pod starts, K8s secrets deleted when pods delete, less GitOps-friendly | Pod lifecycle dependency conflicts with declarative GitOps model |
| Sealed Secrets | Simple, Bitnami supported | Requires kubeseal CLI, secrets still stored in Git (encrypted), no rotation | No automatic secret rotation, additional tooling required |
| Direct K8s Secrets | Simple, native | No rotation, secrets in Git (bad practice), manual management | Security anti-pattern, doesn't meet FR-006 |

**Key Configuration**:
```yaml
# SecretStore connecting to Azure Key Vault
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "https://<vault-name>.vault.azure.net"
      serviceAccountRef:
        name: external-secrets-sa
        namespace: external-secrets
```

---

### 2. ArgoCD Ingress Configuration for Azure Web App Routing

**Decision**: Use Azure Web App Routing ingress class with TLS termination at ingress

**Rationale**:
- Consistent with existing n8n ingress configuration (`ingressClassName: webapprouting.kubernetes.azure.com`)
- Azure-managed ingress controller with built-in integration
- cert-manager already configured for Let's Encrypt (`cert-manager.io/cluster-issuer: "letsencrypt-prod"`)
- TLS termination at ingress with HTTP backend (ArgoCD server runs with `--insecure` flag)

**Alternatives Considered**:

| Option | Pros | Cons | Why Rejected |
|--------|------|------|--------------|
| SSL Passthrough | End-to-end encryption | More complex, requires ArgoCD TLS cert management | Unnecessary complexity, TLS at ingress sufficient |
| nginx-ingress controller | More features, widely used | Different from existing setup, additional controller | Inconsistent with existing n8n configuration |
| LoadBalancer Service | Simple, direct access | No hostname routing, no cert-manager integration | Doesn't support TLS certificates easily |

**Key Configuration**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # ArgoCD runs --insecure
spec:
  ingressClassName: webapprouting.kubernetes.azure.com
  tls:
  - hosts:
    - argocd.ii-us.com
    secretName: argocd-tls
  rules:
  - host: argocd.ii-us.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
```

**ArgoCD Server Configuration** (to run in insecure mode for TLS termination at ingress):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  server.insecure: "true"
```

---

### 3. Existing Secrets Requiring Migration to AKV

**Decision**: Migrate all secrets currently in `k8s/secrets/n8n-secrets.yaml`

**Secrets Identified**:

| Secret Name | Current Location | AKV Secret Name | Purpose |
|-------------|------------------|-----------------|---------|
| `N8N_ENCRYPTION_KEY` | k8s/secrets/n8n-secrets.yaml | `n8n-encryption-key` | n8n data encryption |
| ArgoCD admin password | argocd-initial-admin-secret (auto-generated) | `argocd-admin-password` | ArgoCD UI access |

**Migration Strategy**:
1. Create secrets in Azure Key Vault first
2. Install External Secrets Operator
3. Create ClusterSecretStore for AKV connection
4. Create ExternalSecret resources to sync secrets
5. Update deployments to reference synced secrets
6. Remove plain-text secret manifests from Git
7. Verify applications function correctly

---

### 4. cert-manager Integration for ArgoCD TLS

**Decision**: Use existing cert-manager with `letsencrypt-prod` ClusterIssuer

**Rationale**:
- Already configured and working for n8n ingress (`k8s/deployment/n8n-ingress.yaml` references it)
- Automatic certificate renewal
- No additional configuration needed

**Key Points**:
- Annotation `cert-manager.io/cluster-issuer: "letsencrypt-prod"` triggers certificate generation
- Certificate stored in `secretName` specified in ingress TLS section
- cert-manager handles renewal before expiration (default: 30 days before)

---

### 5. ArgoCD Authentication Strategy

**Decision**: Use local accounts with admin password stored in AKV

**Rationale**:
- Simplest initial setup
- No external IdP dependency
- Admin password secured in AKV
- Can upgrade to SSO/OIDC later if needed

**Alternatives Considered**:

| Option | Pros | Cons | Why Rejected |
|--------|------|------|--------------|
| Azure AD OIDC | Enterprise SSO, MFA | Complex setup, requires Azure AD app registration | Overengineering for initial setup |
| Dex + LDAP | Flexible, standard | Requires Dex deployment, LDAP server | Additional infrastructure |
| GitHub OAuth | Easy for dev teams | Requires GitHub org configuration | Not suitable for production without org |

**Implementation**:
- ArgoCD generates initial admin password in `argocd-initial-admin-secret`
- Extract and store in AKV: `argocd-admin-password`
- Create ExternalSecret to sync back to cluster
- Update ArgoCD secret reference

---

### 6. Secret Rotation Strategy

**Decision**: ESO automatic refresh with 4-hour interval

**Rationale**:
- Balance between security (frequent updates) and API costs (fewer Key Vault calls)
- No pod restarts required
- Applications read updated secrets from mounted files or environment variables

**Configuration**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-secrets
spec:
  refreshInterval: 4h  # Sync every 4 hours
  # ...
```

**Manual Rotation Process**:
1. Update secret value in Azure Key Vault
2. Wait for refresh interval OR trigger manual sync:
   ```bash
   kubectl annotate es n8n-secrets force-sync=$(date +%s) --overwrite -n n8n-prod
   ```
3. Verify secret updated in Kubernetes

---

## Azure Infrastructure Requirements

### Azure Key Vault Setup

1. **Create Key Vault**:
   ```bash
   az keyvault create \
     --name ii-n8n-secrets \
     --resource-group <rg-name> \
     --location eastus \
     --enable-rbac-authorization
   ```

2. **Create Managed Identity for ESO**:
   ```bash
   az identity create \
     --name external-secrets-identity \
     --resource-group <rg-name>
   ```

3. **Assign Key Vault RBAC**:
   ```bash
   az role assignment create \
     --role "Key Vault Secrets User" \
     --assignee <identity-principal-id> \
     --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/ii-n8n-secrets
   ```

4. **Enable Workload Identity on AKS**:
   ```bash
   az aks update \
     --name <cluster-name> \
     --resource-group <rg-name> \
     --enable-workload-identity \
     --enable-oidc-issuer
   ```

5. **Create Federated Credential**:
   ```bash
   az identity federated-credential create \
     --name external-secrets-federated \
     --identity-name external-secrets-identity \
     --resource-group <rg-name> \
     --issuer <AKS-OIDC-ISSUER-URL> \
     --subject system:serviceaccount:external-secrets:external-secrets-sa
   ```

---

## External Secrets Operator Installation

```bash
# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install ESO
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

---

## References

- [External Secrets Operator - Azure Key Vault Provider](https://external-secrets.io/latest/provider/azure-key-vault/)
- [Azure Key Vault CSI Driver Documentation](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
- [ArgoCD Ingress Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/)
- [cert-manager with Let's Encrypt](https://cert-manager.io/docs/tutorials/acme/nginx-ingress/)
- [Azure Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
