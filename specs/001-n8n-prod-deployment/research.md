# Research: n8n Production Deployment

**Feature Branch**: `001-n8n-prod-deployment` | **Date**: 2025-12-16

## Research Topics

### 1. ArgoCD Image Updater Semver Configuration

**Decision**: Use semver update strategy with `1.x` constraint pattern

**Rationale**:
- Allows automatic updates for minor versions and patches within major version 1
- Prevents breaking changes from major version upgrades (e.g., 2.0.0)
- Git write-back to kustomization maintains GitOps state integrity
- Production-safe with explicit tag filtering

**Configuration Pattern**:
```yaml
annotations:
  argocd-image-updater.argoproj.io/image-list: n8n=n8nio/n8n
  argocd-image-updater.argoproj.io/n8n.update-strategy: semver
  argocd-image-updater.argoproj.io/n8n.allow-tags: regexp:^1\.[0-9]+\.[0-9]+$
  argocd-image-updater.argoproj.io/n8n.ignore-tags: latest,edge,nightly,dev,alpha,beta
  argocd-image-updater.argoproj.io/write-back-method: git
  argocd-image-updater.argoproj.io/write-back-target: kustomization
  argocd-image-updater.argoproj.io/git-branch: main
```

**Alternatives Considered**:
- `digest` strategy: Rejected - makes 3 API calls per check, unnecessary for semver releases
- `latest` strategy: Rejected - no version constraint control
- Manual updates: Rejected - doesn't meet automation requirements

**Critical Requirements**:
- Application must track `targetRevision: main` (branch, not tag/SHA)
- Current image tag must be semver format (e.g., `1.72`, not `latest`)
- Git credentials secret required in `argocd` namespace

---

### 2. Azure Blob Storage Lifecycle Policies for 30-Day Retention

**Decision**: Use Azure Lifecycle Management policy (not in-script deletion)

**Rationale**:
- Zero compute costs - fully managed by Azure
- Automatic processing without infrastructure overhead
- More reliable than script-based deletion
- Better audit trail and monitoring integration

**Configuration Pattern**:
```json
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
```

**Azure CLI Deployment**:
```bash
az storage account management-policy create \
    --account-name <storage-account-name> \
    --policy @lifecycle-policy.json \
    --resource-group <resource-group>
```

**Alternatives Considered**:
- In-script deletion (current implementation): Kept as fallback but lifecycle policy is primary
- Azure Functions timer: Rejected - unnecessary compute costs
- Manual cleanup: Rejected - operational overhead

**Important Considerations**:
- Lifecycle policies take up to 24 hours to take effect
- Processing can take multiple days for large accounts
- Recommend keeping in-script deletion as backup mechanism

---

### 3. Kubernetes CronJob Timezone Handling

**Decision**: Use `timeZone` field (Kubernetes 1.27+)

**Rationale**:
- Native Kubernetes support since 1.27
- More reliable than calculating UTC offsets manually
- Clear configuration - `America/New_York` for 2 AM local time

**Configuration Pattern**:
```yaml
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  timeZone: "America/New_York"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  startingDeadlineSeconds: 3600
```

**Alternatives Considered**:
- UTC-based schedule with manual offset: Rejected - DST handling issues
- External cron scheduler: Rejected - unnecessary complexity
- Azure Logic Apps: Rejected - not GitOps-friendly

**Best Practices Applied**:
- `concurrencyPolicy: Forbid` prevents overlapping backup jobs
- `startingDeadlineSeconds: 3600` allows 1-hour window for missed schedules
- `ttlSecondsAfterFinished: 86400` cleans up completed jobs after 24 hours

---

### 4. Network Policy Patterns for Ingress-Only Access

**Decision**: Default-deny with explicit ingress allowlist

**Rationale**:
- Zero-trust approach - deny all traffic by default
- Only allows traffic from ingress controller namespace
- Blocks pod-to-pod communication from unauthorized namespaces

**Configuration Pattern**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: n8n-network-policy
  namespace: n8n-prod
spec:
  podSelector:
    matchLabels:
      app: n8n
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 5678
  egress:
    - to:
        - namespaceSelector: {}  # Allow egress to any namespace (for webhooks)
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
    - to:  # DNS
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
```

**Alternatives Considered**:
- No network policy: Rejected - doesn't meet security requirements
- Service mesh (Istio): Rejected - unnecessary complexity for single-app deployment
- Calico advanced policies: Rejected - standard K8s NetworkPolicy sufficient

---

## Edge Case Resolutions

Based on the spec's edge cases, here are the recommended handling strategies:

| Edge Case | Resolution |
|-----------|------------|
| Git repository unavailable during image update | Image Updater retries with backoff; change is queued until git accessible |
| Azure Storage auth failure during backup | Job fails with exit code; failedJobsHistoryLimit=5 preserves logs for diagnosis |
| Encryption key secret deleted/corrupted | n8n fails to start; readinessProbe prevents traffic routing; restore from backup |
| PVC storage runs out of space | Pod eviction; HPA won't help; requires manual PVC expansion or data cleanup |
| ArgoCD sync fails due to invalid manifests | syncPolicy.retry with exponential backoff; manual intervention required if persistent |

---

## Summary

All technical unknowns have been resolved with production-ready patterns:

1. **Image Updates**: Semver constraint with git write-back
2. **Backup Retention**: Azure Lifecycle Management policy
3. **Backup Scheduling**: Native K8s CronJob timezone support
4. **Network Security**: Default-deny NetworkPolicy with ingress allowlist

No blocking clarifications remain. Ready for Phase 1 design artifacts.
