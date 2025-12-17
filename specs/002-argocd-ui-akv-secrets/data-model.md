# Data Model: ArgoCD Web UI Setup and Azure Key Vault Secrets Migration

**Date**: 2025-12-16
**Feature Branch**: `002-argocd-ui-akv-secrets`

## Overview

This feature does not introduce traditional application entities but defines Kubernetes custom resources and Azure resources for secrets management and ArgoCD configuration.

## Kubernetes Resources

### 1. ClusterSecretStore

**Purpose**: Cluster-wide connection to Azure Key Vault for External Secrets Operator

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `metadata.name` | string | Resource identifier | Yes |
| `spec.provider.azurekv.vaultUrl` | string | Azure Key Vault URL | Yes |
| `spec.provider.azurekv.authType` | enum | `WorkloadIdentity`, `ManagedIdentity`, `ServicePrincipal` | Yes |
| `spec.provider.azurekv.serviceAccountRef` | object | Reference to ServiceAccount for auth | Conditional |

**Relationships**: Referenced by ExternalSecret resources

---

### 2. ExternalSecret

**Purpose**: Defines mapping between AKV secrets and Kubernetes secrets

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `metadata.name` | string | Resource identifier | Yes |
| `metadata.namespace` | string | Target namespace for synced secret | Yes |
| `spec.refreshInterval` | duration | How often to sync (e.g., `4h`) | No (default: disabled) |
| `spec.secretStoreRef.name` | string | Reference to ClusterSecretStore | Yes |
| `spec.secretStoreRef.kind` | enum | `ClusterSecretStore` or `SecretStore` | Yes |
| `spec.target.name` | string | Name of Kubernetes Secret to create | Yes |
| `spec.data[].secretKey` | string | Key in target K8s secret | Yes |
| `spec.data[].remoteRef.key` | string | Secret name in AKV | Yes |

**Relationships**: References ClusterSecretStore, creates Kubernetes Secret

**State Transitions**:
- `SecretSynced` → Secret successfully synced from AKV
- `SecretSyncError` → Failed to sync (auth error, AKV unavailable)
- `SecretPending` → Initial state before first sync

---

### 3. ArgoCD Ingress

**Purpose**: Exposes ArgoCD server externally with TLS

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `metadata.name` | string | Resource identifier | Yes |
| `metadata.namespace` | string | Must be `argocd` | Yes |
| `metadata.annotations` | map | cert-manager, nginx settings | Yes |
| `spec.ingressClassName` | string | `webapprouting.kubernetes.azure.com` | Yes |
| `spec.tls[].hosts` | []string | Hostnames for TLS | Yes |
| `spec.tls[].secretName` | string | TLS certificate secret | Yes |
| `spec.rules[].host` | string | Hostname for routing | Yes |
| `spec.rules[].http.paths[].backend` | object | ArgoCD server service | Yes |

**Relationships**: References TLS secret (created by cert-manager)

---

### 4. ArgoCD ConfigMap (argocd-cm)

**Purpose**: ArgoCD server configuration including URL and features

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `data.url` | string | External ArgoCD URL | Yes |
| `data.admin.enabled` | string | Enable/disable admin user | No |
| `data.dex.config` | string | Dex OIDC configuration | No |

---

### 5. ArgoCD CMD Params ConfigMap (argocd-cmd-params-cm)

**Purpose**: ArgoCD server command-line parameters

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `data.server.insecure` | string | Run without TLS (`true`/`false`) | Yes |

---

## Azure Resources

### 1. Azure Key Vault

**Purpose**: Secure storage for application secrets

| Property | Type | Description |
|----------|------|-------------|
| Name | string | `ii-n8n-secrets` (example) |
| Resource Group | string | AKS resource group |
| SKU | enum | `standard` |
| RBAC Authorization | boolean | `true` (recommended) |
| Soft Delete | boolean | `true` (default) |
| Purge Protection | boolean | Recommended for production |

**Secrets Stored**:

| Secret Name | Purpose | Used By |
|-------------|---------|---------|
| `n8n-encryption-key` | n8n data encryption | n8n deployment |
| `argocd-admin-password` | ArgoCD admin login | ArgoCD server |

---

### 2. Azure Managed Identity

**Purpose**: Identity for External Secrets Operator to access Key Vault

| Property | Type | Description |
|----------|------|-------------|
| Name | string | `external-secrets-identity` |
| Resource Group | string | AKS resource group |
| Federated Credential | object | Links to K8s ServiceAccount |

**RBAC Assignments**:
- Role: `Key Vault Secrets User`
- Scope: Key Vault resource

---

## Secret Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Azure Key Vault                                │
│  ┌─────────────────────┐     ┌──────────────────────────┐              │
│  │ n8n-encryption-key  │     │ argocd-admin-password    │              │
│  └─────────────────────┘     └──────────────────────────┘              │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   │ Workload Identity Auth
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    External Secrets Operator                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    ClusterSecretStore                            │   │
│  │                    (azure-keyvault)                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
           ┌───────────────────────┼───────────────────────┐
           │                       │                       │
           ▼                       ▼                       ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│   ExternalSecret    │ │   ExternalSecret    │ │  Future secrets...  │
│   (n8n-secrets)     │ │  (argocd-secrets)   │ │                     │
│   namespace: n8n    │ │  namespace: argocd  │ │                     │
└──────────┬──────────┘ └──────────┬──────────┘ └─────────────────────┘
           │                       │
           ▼                       ▼
┌─────────────────────┐ ┌─────────────────────┐
│  Kubernetes Secret  │ │  Kubernetes Secret  │
│    (n8n-secrets)    │ │  (argocd-secrets)   │
└──────────┬──────────┘ └──────────┬──────────┘
           │                       │
           ▼                       ▼
┌─────────────────────┐ ┌─────────────────────┐
│   n8n Deployment    │ │   ArgoCD Server     │
│   (env: N8N_...)    │ │  (admin password)   │
└─────────────────────┘ └─────────────────────┘
```

## Validation Rules

### ExternalSecret

1. `refreshInterval` must be valid duration string (e.g., `1h`, `30m`, `4h`)
2. `secretStoreRef.name` must reference existing ClusterSecretStore
3. `remoteRef.key` must exist in Azure Key Vault
4. Target secret name must be valid Kubernetes name (lowercase, alphanumeric, hyphens)

### Ingress

1. `host` must be valid DNS name
2. `secretName` for TLS must not conflict with existing secrets
3. `ingressClassName` must match installed ingress controller

### Azure Key Vault

1. Secret names: alphanumeric and hyphens only, 1-127 characters
2. Secret values: max 25KB
3. RBAC: Identity must have `Key Vault Secrets User` role minimum

## Relationships Diagram

```
┌─────────────────────┐
│  Azure Managed      │
│    Identity         │◄─────────────────────────────────────┐
└─────────┬───────────┘                                      │
          │ Federated                                         │
          │ Credential                                        │
          ▼                                                   │
┌─────────────────────┐     ┌─────────────────────┐          │
│  K8s ServiceAccount │     │  Azure Key Vault    │          │
│  (external-secrets) │────▶│  (ii-n8n-secrets)   │          │
└─────────────────────┘     └─────────────────────┘          │
          │                           ▲                       │
          │ used by                   │ reads                 │
          ▼                           │                       │
┌─────────────────────┐     ┌─────────────────────┐          │
│  ESO Controller     │────▶│ ClusterSecretStore  │──────────┘
└─────────────────────┘     └─────────────────────┘
          │                           ▲
          │ manages                   │ references
          ▼                           │
┌─────────────────────┐               │
│  ExternalSecret     │───────────────┘
└─────────┬───────────┘
          │ creates
          ▼
┌─────────────────────┐
│  Kubernetes Secret  │
└─────────────────────┘
```
