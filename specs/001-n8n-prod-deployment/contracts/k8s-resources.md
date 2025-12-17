# Kubernetes Resource Contracts

**Feature Branch**: `001-n8n-prod-deployment` | **Date**: 2025-12-16

## Resource Inventory

This document serves as the contract for all Kubernetes resources in the n8n production deployment.

---

## Resource Manifest Index

| Resource Type | Name | Namespace | File Path | Status |
|--------------|------|-----------|-----------|--------|
| Namespace | n8n-prod | - | `k8s/namespace.yaml` | Exists |
| Deployment | n8n | n8n-prod | `k8s/deployment/n8n-deployment.yaml` | Exists |
| Service | n8n | n8n-prod | `k8s/deployment/n8n-service.yaml` | Exists |
| Ingress | n8n | n8n-prod | `k8s/deployment/n8n-ingress.yaml` | Exists |
| HPA | n8n-hpa | n8n-prod | `k8s/deployment/hpa.yaml` | Exists |
| PDB | n8n-pdb | n8n-prod | `k8s/deployment/pdb.yaml` | Exists |
| PVC | n8n-data | n8n-prod | `k8s/storage/pvc.yaml` | Exists |
| Secret | n8n-secrets | n8n-prod | `k8s/secrets/n8n-secrets.yaml` | Template Only |
| NetworkPolicy | n8n-network-policy | n8n-prod | `k8s/network/network-policy.yaml` | Exists |
| CronJob | n8n-backup | n8n-prod | `k8s/backup/backup-cronjob.yaml` | Exists |
| ServiceAccount | n8n | n8n-prod | `k8s/rbac/service-account.yaml` | Exists |
| ServiceAccount | n8n-backup | n8n-prod | `k8s/rbac/backup-service-account.yaml` | Exists |
| Kustomization | - | - | `k8s/kustomization.yaml` | Exists |
| Application | n8n-prod | argocd | `gitops/argo-application.yaml` | Exists |

---

## Required Secrets (Not in Git)

| Secret Name | Namespace | Keys | Creation Method |
|-------------|-----------|------|-----------------|
| n8n-secrets | n8n-prod | N8N_ENCRYPTION_KEY | `kubectl create secret` |
| git-creds | argocd | username, password | `kubectl create secret` |

### Secret Creation Commands

```bash
# n8n encryption key
ENCRYPTION_KEY=$(openssl rand -hex 32)
kubectl create secret generic n8n-secrets \
  --from-literal=N8N_ENCRYPTION_KEY="$ENCRYPTION_KEY" \
  -n n8n-prod

# Git credentials for ArgoCD Image Updater
kubectl create secret generic git-creds \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_PAT \
  -n argocd
```

---

## External Dependencies

| Dependency | Type | Purpose | Required |
|------------|------|---------|----------|
| Azure Storage Account | Azure Service | Backup storage | Yes |
| Ingress Controller | K8s Controller | External access | Yes |
| cert-manager | K8s Controller | TLS certificates | Yes |
| ArgoCD | K8s Application | GitOps deployment | Yes |
| ArgoCD Image Updater | K8s Application | Auto image updates | Yes |

---

## Configuration Values Requiring Update

| File | Field | Current Value | Action |
|------|-------|---------------|--------|
| `gitops/argo-application.yaml` | spec.source.repoURL | `YOUR_ORG/II-n8n.git` | Update to actual repo |
| `k8s/backup/backup-cronjob.yaml` | env.AZURE_STORAGE_ACCOUNT | `YOUR_STORAGE_ACCOUNT_NAME` | Update to actual account |

---

## API Versions

| Resource | API Version | Notes |
|----------|-------------|-------|
| Deployment | apps/v1 | Stable |
| Service | v1 | Stable |
| Ingress | networking.k8s.io/v1 | Stable |
| HPA | autoscaling/v2 | Stable |
| PDB | policy/v1 | Stable |
| NetworkPolicy | networking.k8s.io/v1 | Stable |
| CronJob | batch/v1 | Stable (timeZone requires K8s 1.27+) |
| Application | argoproj.io/v1alpha1 | ArgoCD CRD |

---

## Validation Checklist

Before deployment, verify:

- [ ] ArgoCD Application repoURL updated to actual repository
- [ ] Azure Storage Account name configured in backup CronJob
- [ ] n8n-secrets created with encryption key
- [ ] git-creds secret created in argocd namespace
- [ ] DNS configured for n8n.ii-us.com pointing to ingress
- [ ] TLS certificate available (cert-manager or manual)
- [ ] Azure managed identity has Storage Blob Data Contributor role

---

## Kustomize Structure

```yaml
# k8s/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - deployment/n8n-deployment.yaml
  - deployment/n8n-service.yaml
  - deployment/n8n-ingress.yaml
  - deployment/hpa.yaml
  - deployment/pdb.yaml
  - storage/pvc.yaml
  - secrets/n8n-secrets.yaml
  - network/network-policy.yaml
  - backup/backup-cronjob.yaml
  - rbac/service-account.yaml
  - rbac/backup-service-account.yaml

images:
  - name: n8nio/n8n
    newTag: "1.72"  # Updated by ArgoCD Image Updater

commonLabels:
  app.kubernetes.io/managed-by: argocd
  environment: production
```

---

## Health Check Endpoints

| Component | Endpoint | Expected Response |
|-----------|----------|-------------------|
| n8n | GET /healthz | 200 OK |
| n8n metrics | GET /metrics | Prometheus format |

---

## Resource Quotas (Recommended)

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: n8n-quota
  namespace: n8n-prod
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "10"
    limits.memory: 20Gi
    persistentvolumeclaims: "2"
    pods: "10"
```

---

## Network Contract

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| ingress-nginx | n8n pods | 5678 | TCP | HTTP traffic |
| n8n pods | Any | 443 | TCP | Outbound webhooks |
| n8n pods | Any | 80 | TCP | Outbound HTTP |
| n8n pods | kube-system | 53 | UDP | DNS resolution |
| backup job | Azure Storage | 443 | TCP | Backup upload |
