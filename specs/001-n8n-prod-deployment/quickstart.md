# Quickstart: n8n Production Deployment

**Feature Branch**: `001-n8n-prod-deployment` | **Date**: 2025-12-16

This guide provides step-by-step instructions to deploy n8n to production on AKS with ArgoCD.

---

## Prerequisites

Before starting, ensure you have:

- [ ] AKS cluster provisioned and accessible via `kubectl`
- [ ] ArgoCD installed on the cluster (`argocd` namespace)
- [ ] ArgoCD Image Updater installed
- [ ] Ingress controller (nginx-ingress) installed
- [ ] cert-manager installed for TLS certificates
- [ ] Azure Storage Account created
- [ ] DNS configured for `n8n.ii-us.com`
- [ ] GitHub repository access (PAT with repo scope)

---

## Step 1: Configure Repository URL

Update the ArgoCD Application with your actual repository URL:

```bash
# Edit gitops/argo-application.yaml
# Change: repoURL: 'https://github.com/YOUR_ORG/II-n8n.git'
# To: repoURL: 'https://github.com/<your-org>/II-n8n.git'
```

---

## Step 2: Create Secrets

### n8n Encryption Key

```bash
# Generate encryption key
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Create secret
kubectl create namespace n8n-prod --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic n8n-secrets \
  --from-literal=N8N_ENCRYPTION_KEY="$ENCRYPTION_KEY" \
  -n n8n-prod
```

### Git Credentials for Image Updater

```bash
kubectl create secret generic git-creds \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_PAT \
  -n argocd
```

---

## Step 3: Configure Azure Storage

### Update Backup CronJob

```bash
# Edit k8s/backup/backup-cronjob.yaml
# Change: value: "YOUR_STORAGE_ACCOUNT_NAME"
# To: value: "<your-storage-account>"
```

### Grant AKS Managed Identity Access

```bash
# Get AKS managed identity
AKS_IDENTITY=$(az aks show \
  --resource-group <your-rg> \
  --name <your-aks> \
  --query identityProfile.kubeletidentity.clientId -o tsv)

# Grant Storage Blob Data Contributor role
az role assignment create \
  --assignee $AKS_IDENTITY \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-account>
```

### Create Backup Container

```bash
az storage container create \
  --name n8n-backups \
  --account-name <your-storage-account>
```

### Configure Lifecycle Policy (30-day retention)

```bash
cat > lifecycle-policy.json << 'EOF'
{
  "rules": [
    {
      "name": "Delete-n8n-Backups-After-30-Days",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["n8n-backup-"]
        },
        "actions": {
          "baseBlob": {
            "delete": { "daysAfterModificationGreaterThan": 30 }
          }
        }
      }
    }
  ]
}
EOF

az storage account management-policy create \
  --account-name <your-storage-account> \
  --policy @lifecycle-policy.json \
  --resource-group <your-rg>
```

---

## Step 4: Deploy with ArgoCD

### Apply ArgoCD Application

```bash
kubectl apply -f gitops/argo-application.yaml
```

### Monitor Deployment

```bash
# Watch ArgoCD sync status
argocd app get n8n-prod

# Or via kubectl
kubectl get application n8n-prod -n argocd -w

# Watch pods
kubectl get pods -n n8n-prod -w
```

### Force Sync (if needed)

```bash
argocd app sync n8n-prod
```

---

## Step 5: Verify Deployment

### Check Pod Status

```bash
kubectl get pods -n n8n-prod
# Expected: n8n-xxxxx Running
```

### Check Services

```bash
kubectl get svc -n n8n-prod
# Expected: n8n ClusterIP 10.x.x.x 80/TCP
```

### Check Ingress

```bash
kubectl get ingress -n n8n-prod
# Expected: n8n with ADDRESS and HTTPS
```

### Access n8n

Open `https://n8n.ii-us.com` in your browser. You should see the n8n setup page.

---

## Step 6: Verify Automatic Updates

### Check Image Updater Status

```bash
kubectl logs -f deployment/argocd-image-updater -n argocd
```

### Verify Annotations

```bash
kubectl get application n8n-prod -n argocd \
  -o jsonpath='{.metadata.annotations}' | jq
```

---

## Step 7: Test Backup

### Manual Backup Trigger

```bash
kubectl create job --from=cronjob/n8n-backup manual-backup -n n8n-prod
```

### Monitor Backup Job

```bash
kubectl logs -f job/manual-backup -n n8n-prod
```

### Verify Backup in Azure

```bash
az storage blob list \
  --container-name n8n-backups \
  --account-name <your-storage-account> \
  --output table
```

---

## Troubleshooting

### Pod Not Starting

```bash
kubectl describe pod -l app=n8n -n n8n-prod
kubectl logs -l app=n8n -n n8n-prod
```

### ArgoCD Sync Issues

```bash
argocd app get n8n-prod
argocd app sync n8n-prod --force
```

### Image Updater Not Working

```bash
# Check logs
kubectl logs deployment/argocd-image-updater -n argocd

# Verify git credentials
kubectl get secret git-creds -n argocd

# Test image detection
kubectl exec -it deployment/argocd-image-updater -n argocd \
  -- argocd-image-updater test n8nio/n8n:1.x --semver
```

### Backup Failures

```bash
# Check job status
kubectl get jobs -n n8n-prod

# Check failed job logs
kubectl logs job/<job-name> -n n8n-prod

# Verify Azure access
kubectl exec -it deployment/n8n -n n8n-prod -- az login --identity
```

---

## Quick Reference

| Component | Command |
|-----------|---------|
| View pods | `kubectl get pods -n n8n-prod` |
| View logs | `kubectl logs -f deployment/n8n -n n8n-prod` |
| ArgoCD status | `argocd app get n8n-prod` |
| Force sync | `argocd app sync n8n-prod` |
| Manual backup | `kubectl create job --from=cronjob/n8n-backup test-backup -n n8n-prod` |
| Scale manually | `kubectl scale deployment/n8n --replicas=3 -n n8n-prod` |

---

## Recovery Procedure

To restore from backup:

1. Download backup from Azure Storage
2. Stop n8n deployment: `kubectl scale deployment/n8n --replicas=0 -n n8n-prod`
3. Extract backup to PVC
4. Start n8n: `kubectl scale deployment/n8n --replicas=1 -n n8n-prod`

See `SETUP.md` for detailed recovery instructions.
