# Data Model: n8n Production Deployment

**Feature Branch**: `001-n8n-prod-deployment` | **Date**: 2025-12-16

## Kubernetes Resource Definitions

This document defines the Kubernetes resources, their relationships, and validation rules for the n8n production deployment.

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ArgoCD Namespace                                │
│  ┌─────────────────────┐                                                    │
│  │  ArgoCD Application │──────────────────────────────────────────────┐     │
│  │  (n8n-prod)         │                                              │     │
│  │  - Image Updater    │                                              │     │
│  │  - Git write-back   │                                              │     │
│  └─────────────────────┘                                              │     │
│                                                                        │     │
│  ┌─────────────────────┐                                              │     │
│  │  Secret             │                                              │     │
│  │  (git-creds)        │ ← Image Updater git authentication           │     │
│  └─────────────────────┘                                              │     │
└────────────────────────────────────────────────────────────────────────│─────┘
                                                                         │
                                    Syncs manifests from git             │
                                                                         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              n8n-prod Namespace                              │
│                                                                              │
│  ┌─────────────────────┐     ┌─────────────────────┐                        │
│  │  Deployment         │────▶│  Service            │                        │
│  │  (n8n)              │     │  (n8n)              │                        │
│  │  - 1-5 replicas     │     │  - ClusterIP        │                        │
│  │  - Rolling update   │     │  - Port 5678        │                        │
│  └─────────┬───────────┘     └──────────┬──────────┘                        │
│            │                            │                                    │
│            │ mounts                     │ routes to                          │
│            ▼                            ▼                                    │
│  ┌─────────────────────┐     ┌─────────────────────┐                        │
│  │  PVC                │     │  Ingress            │◀── External HTTPS      │
│  │  (n8n-data)         │     │  (n8n)              │                        │
│  │  - 10Gi             │     │  - TLS termination  │                        │
│  │  - ReadWriteOnce    │     │  - n8n.ii-us.com    │                        │
│  └─────────────────────┘     └─────────────────────┘                        │
│                                                                              │
│  ┌─────────────────────┐     ┌─────────────────────┐                        │
│  │  Secret             │     │  NetworkPolicy      │                        │
│  │  (n8n-secrets)      │     │  (n8n-network)      │                        │
│  │  - Encryption key   │     │  - Ingress-only     │                        │
│  └─────────────────────┘     └─────────────────────┘                        │
│                                                                              │
│  ┌─────────────────────┐     ┌─────────────────────┐                        │
│  │  HPA                │     │  PDB                │                        │
│  │  (n8n-hpa)          │     │  (n8n-pdb)          │                        │
│  │  - min: 1, max: 5   │     │  - minAvailable: 1  │                        │
│  │  - CPU target: 80%  │     │                     │                        │
│  └─────────────────────┘     └─────────────────────┘                        │
│                                                                              │
│  ┌─────────────────────┐                                                    │
│  │  CronJob            │──────────────────────────────┐                     │
│  │  (n8n-backup)       │                              │                     │
│  │  - Daily 2 AM       │                              │                     │
│  │  - 30-day retention │                              ▼                     │
│  └─────────────────────┘                    Azure Blob Storage              │
│                                             (n8n-backups container)          │
│  ┌─────────────────────┐     ┌─────────────────────┐                        │
│  │  ServiceAccount     │     │  ServiceAccount     │                        │
│  │  (n8n)              │     │  (n8n-backup)       │                        │
│  │  - Deployment SA    │     │  - Backup job SA    │                        │
│  └─────────────────────┘     └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Resource Specifications

### 1. Namespace

| Field | Value | Description |
|-------|-------|-------------|
| name | `n8n-prod` | Production namespace |
| labels.environment | `production` | Environment identifier |

---

### 2. Deployment (n8n)

| Field | Value | Validation |
|-------|-------|------------|
| name | `n8n` | Required |
| namespace | `n8n-prod` | Must exist |
| replicas | `1` (managed by HPA) | Min 1, Max 5 |
| image | `n8nio/n8n:1.72` | Semver format required |
| containerPort | `5678` | Fixed by n8n |
| serviceAccountName | `n8n` | Must exist |

**Security Context**:
| Field | Value |
|-------|-------|
| runAsNonRoot | `true` |
| runAsUser | `1000` |
| fsGroup | `1000` |
| allowPrivilegeEscalation | `false` |
| capabilities.drop | `ALL` |

**Resources**:
| Type | CPU | Memory |
|------|-----|--------|
| requests | 500m | 1Gi |
| limits | 2000m | 4Gi |

**Environment Variables** (from spec):
| Variable | Source | Required |
|----------|--------|----------|
| N8N_ENCRYPTION_KEY | Secret `n8n-secrets` | Yes |
| N8N_HOST | ConfigMap/inline | Yes |
| N8N_METRICS | inline (`true`) | Yes |

---

### 3. Service

| Field | Value |
|-------|-------|
| name | `n8n` |
| type | `ClusterIP` |
| port | `80` |
| targetPort | `5678` |
| selector | `app: n8n` |

---

### 4. Ingress

| Field | Value |
|-------|-------|
| name | `n8n` |
| className | `nginx` |
| host | `n8n.ii-us.com` |
| tls.secretName | `n8n-tls` |
| path | `/` |
| pathType | `Prefix` |
| backend.service | `n8n:80` |

---

### 5. HorizontalPodAutoscaler

| Field | Value |
|-------|-------|
| name | `n8n-hpa` |
| scaleTargetRef | Deployment/n8n |
| minReplicas | `1` |
| maxReplicas | `5` |
| metrics.cpu.averageUtilization | `80` |
| metrics.memory.averageUtilization | `80` |

---

### 6. PodDisruptionBudget

| Field | Value |
|-------|-------|
| name | `n8n-pdb` |
| selector | `app: n8n` |
| minAvailable | `1` |

---

### 7. PersistentVolumeClaim

| Field | Value |
|-------|-------|
| name | `n8n-data` |
| accessModes | `ReadWriteOnce` |
| storageClassName | `managed-premium` |
| storage | `10Gi` |

---

### 8. Secret (n8n-secrets)

| Key | Description | Source |
|-----|-------------|--------|
| N8N_ENCRYPTION_KEY | 32-byte hex encryption key | Generated via `openssl rand -hex 32` |

**Note**: Secret values are NOT stored in git. Created manually or via external secrets management.

---

### 9. NetworkPolicy

| Field | Value |
|-------|-------|
| name | `n8n-network-policy` |
| podSelector | `app: n8n` |
| policyTypes | Ingress, Egress |
| ingress.from | ingress-nginx namespace |
| ingress.ports | TCP/5678 |
| egress.to | Any (for webhooks) |
| egress.ports | TCP/80, TCP/443, UDP/53 |

---

### 10. CronJob (n8n-backup)

| Field | Value |
|-------|-------|
| name | `n8n-backup` |
| schedule | `0 2 * * *` |
| timeZone | `America/New_York` |
| concurrencyPolicy | `Forbid` |
| backoffLimit | `3` |
| activeDeadlineSeconds | `1800` |
| image | `mcr.microsoft.com/azure-cli:latest` |

**Retention**: 30 days (via Azure Lifecycle Policy + in-script cleanup)

---

### 11. ArgoCD Application

| Field | Value |
|-------|-------|
| name | `n8n-prod` |
| namespace | `argocd` |
| project | `default` |
| source.repoURL | Git repository URL |
| source.path | `k8s` |
| source.targetRevision | `main` |
| destination.namespace | `n8n-prod` |
| syncPolicy.automated | `prune: true, selfHeal: true` |

**Image Updater Annotations**:
| Annotation | Value |
|------------|-------|
| image-list | `n8n=n8nio/n8n` |
| update-strategy | `semver` |
| allow-tags | `regexp:^1\.[0-9]+\.[0-9]+$` |
| ignore-tags | `latest,edge,nightly` |
| write-back-method | `git` |
| write-back-target | `kustomization` |

---

## State Transitions

### Deployment Lifecycle

```
Initial Deploy → Running → Update Available → Updating → Running
                    ↓           ↓
                 Scaling    Failed Update
                    ↓           ↓
              Scaled Out    Rollback
                    ↓           ↓
                Running      Running
```

### Backup Job States

```
Scheduled → Running → Completed → Cleaned Up (after 24h)
              ↓
           Failed → Retry (up to 3x) → Failed Final
```

---

## Validation Rules

1. **Image Tag**: Must match regex `^1\.[0-9]+\.[0-9]+$`
2. **Encryption Key**: Must be exactly 64 hex characters
3. **PVC Size**: Minimum 10Gi recommended for production
4. **Resource Limits**: Memory limit ≥ 2x request for burst handling
5. **Replica Count**: HPA manages; manual setting overridden
6. **TLS Secret**: Must exist before Ingress creation
7. **Network Policy**: Must allow ingress-nginx namespace
