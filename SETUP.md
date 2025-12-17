# n8n Production Deployment Setup Guide

This guide covers the steps required to complete the n8n production deployment with automatic updates.

## Prerequisites

- Azure Kubernetes Service (AKS) cluster
- kubectl configured with cluster access
- ArgoCD installed on the cluster
- Helm 3.x (optional, for some installations)

## Step 1: Install ArgoCD Image Updater

ArgoCD Image Updater automatically updates container images and commits changes back to git.

```bash
# Install ArgoCD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Verify installation
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
```

## Step 2: Configure Git Repository Access

ArgoCD Image Updater needs write access to your git repository to commit image updates.

```bash
# Create a GitHub Personal Access Token with repo scope
# Then create a secret:
kubectl create secret generic git-creds \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_PAT \
  -n argocd

# Or for SSH:
kubectl create secret generic git-creds \
  --from-file=sshPrivateKey=/path/to/private/key \
  -n argocd
```

## Step 3: Update ArgoCD Application Configuration

Edit `gitops/argo-application.yaml` and update the `repoURL` to your actual repository:

```yaml
spec:
  source:
    repoURL: 'https://github.com/YOUR_ORG/II-n8n.git'  # <-- Update this
```

## Step 4: Create n8n Encryption Key

Generate a secure encryption key and create the Kubernetes secret:

```bash
# Generate a secure key
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Create the secret (do NOT commit this to git)
kubectl create secret generic n8n-secrets \
  --from-literal=N8N_ENCRYPTION_KEY="$ENCRYPTION_KEY" \
  -n n8n-prod \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Step 5: Configure Azure Storage for Backups

Update the storage account name in `k8s/backup/backup-cronjob.yaml`:

```yaml
- name: AZURE_STORAGE_ACCOUNT
  value: "YOUR_ACTUAL_STORAGE_ACCOUNT"  # <-- Update this
```

Also ensure:
1. The storage account exists in Azure
2. A container named `n8n-backups` is created
3. The AKS cluster has managed identity access to the storage account

```bash
# Grant storage access to AKS managed identity
az role assignment create \
  --assignee <AKS_MANAGED_IDENTITY_CLIENT_ID> \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<SUB_ID>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<STORAGE_ACCOUNT>
```

## Step 6: Deploy to Cluster

### Option A: Using ArgoCD (Recommended)

```bash
# Apply the ArgoCD Application
kubectl apply -f gitops/argo-application.yaml

# Monitor sync status
argocd app get n8n-prod
argocd app sync n8n-prod
```

### Option B: Direct kubectl apply

```bash
# Apply all resources using kustomize
kubectl apply -k k8s/
```

## Step 7: Verify Deployment

```bash
# Check pod status
kubectl get pods -n n8n-prod

# Check services
kubectl get svc -n n8n-prod

# Check ingress
kubectl get ingress -n n8n-prod

# View logs
kubectl logs -f deployment/n8n -n n8n-prod

# Verify automatic update configuration
kubectl get application n8n-prod -n argocd -o yaml | grep -A20 "annotations:"
```

## Step 8: Verify Automatic Updates

Check ArgoCD Image Updater logs:

```bash
kubectl logs -f deployment/argocd-image-updater -n argocd
```

You should see output like:
```
time="..." level=info msg="Starting image update cycle"
time="..." level=info msg="Processing application n8n-prod"
time="..." level=info msg="Setting new image to n8nio/n8n:1.XX.X"
```

## Troubleshooting

### Image Updater not finding new versions

```bash
# Check image updater logs
kubectl logs deployment/argocd-image-updater -n argocd

# Verify annotations on the Application
kubectl get application n8n-prod -n argocd -o jsonpath='{.metadata.annotations}'
```

### ArgoCD sync issues

```bash
# Force sync
argocd app sync n8n-prod --force

# Check sync status
argocd app get n8n-prod
```

### Pod not starting

```bash
# Describe pod for events
kubectl describe pod -l app=n8n -n n8n-prod

# Check PVC status
kubectl get pvc -n n8n-prod
```

## Configuration Reference

| Component | File | Purpose |
|-----------|------|---------|
| Deployment | `k8s/deployment/n8n-deployment.yaml` | Main n8n container configuration |
| Service | `k8s/deployment/n8n-service.yaml` | Internal ClusterIP service |
| Ingress | `k8s/deployment/n8n-ingress.yaml` | External HTTPS access |
| HPA | `k8s/deployment/hpa.yaml` | Horizontal Pod Autoscaler |
| PDB | `k8s/deployment/pdb.yaml` | Pod Disruption Budget |
| Network Policy | `k8s/network/network-policy.yaml` | Network security rules |
| Backup | `k8s/backup/backup-cronjob.yaml` | Daily backup to Azure Storage |
| ArgoCD App | `gitops/argo-application.yaml` | GitOps + auto-update config |

## Security Checklist

- [ ] Encryption key is securely generated and stored
- [ ] Secrets are NOT committed to git (use external secrets management)
- [ ] Network policies are enabled
- [ ] TLS is configured for ingress
- [ ] RBAC is properly configured
- [ ] Security context is set (non-root, dropped capabilities)

## Monitoring

n8n exports Prometheus metrics on port 5678 at `/metrics`. Configure your monitoring stack:

```yaml
# Example ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: n8n
  namespace: n8n-prod
spec:
  selector:
    matchLabels:
      app: n8n
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```
