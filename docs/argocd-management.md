# ArgoCD Management Guide

This guide covers ArgoCD operations for the II-n8n Kubernetes cluster.

## Overview

ArgoCD manages deployments using the **App-of-Apps pattern**:

```
root (argocd/applications/)
├── argocd         (Helm: argo-cd 7.7.10)
├── cert-manager   (Helm: cert-manager v1.19.1)
├── external-secrets (Helm: external-secrets 0.14.4)
├── keel           (Helm: keel 1.0.5)
└── n8n-prod       (Kustomize: k8s/)
```

**Git Repository:** `https://github.com/iius-rcox/II-n8n.git`

## Application Reference

| App | Type | Namespace | Purpose |
|-----|------|-----------|---------|
| `root` | Kustomize | argocd | App-of-apps controller |
| `argocd` | Helm | argocd | ArgoCD itself (self-managed) |
| `cert-manager` | Helm | cert-manager | TLS certificate management |
| `external-secrets` | Helm | external-secrets | Azure Key Vault integration |
| `keel` | Helm | keel | Automatic image updates |
| `n8n-prod` | Kustomize | n8n-prod | Workflow automation platform |

### Disabled Applications

These are defined but commented out in `kustomization.yaml`:

- **monitoring** - Prometheus stack (disabled: insufficient cluster capacity)
- **supabase** - Database/Auth platform (disabled: Helm repo issues, managed manually)

---

# Part 1: Web UI Guide

## Accessing the ArgoCD UI

### URL and Login

1. Open your browser and navigate to: **https://k8.ii-us.com**

2. You'll see the ArgoCD login page with username/password fields

3. Enter credentials:
   - **Username:** `admin`
   - **Password:** Retrieve using CLI (see CLI section) or ask your administrator

4. Click **"Sign In"**

### First-Time Orientation

After logging in, you'll see the **Applications Dashboard**:

```
┌─────────────────────────────────────────────────────────────────────┐
│  [+ NEW APP]  [Sync Apps]  [Refresh Apps]          🔍 Search...     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│   │   root      │  │  argocd     │  │ cert-manager│                │
│   │   Synced ✓  │  │  Synced ✓   │  │  Synced ✓   │                │
│   │   Healthy   │  │  Healthy    │  │  Healthy    │                │
│   └─────────────┘  └─────────────┘  └─────────────┘                │
│                                                                     │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│   │external-sec │  │    keel     │  │  n8n-prod   │                │
│   │  Synced ✓   │  │  Synced ✓   │  │  Synced ✓   │                │
│   │  Healthy    │  │  Healthy    │  │  Healthy    │                │
│   └─────────────┘  └─────────────┘  └─────────────┘                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Understanding Application Cards

Each application card shows:

| Element | Meaning |
|---------|---------|
| **App Name** | The application identifier (e.g., `n8n-prod`) |
| **Sync Status** | `Synced` (green) = matches Git, `OutOfSync` (yellow) = differs from Git |
| **Health Status** | `Healthy` (green), `Progressing` (blue), `Degraded` (red), `Missing` (yellow) |
| **Repository Icon** | Git icon shows the source repository |
| **Destination** | Shows target namespace/cluster |

### Status Colors

- **Green (Synced/Healthy):** Everything is good
- **Yellow (OutOfSync/Missing):** Needs attention but not critical
- **Blue (Progressing):** Operation in progress
- **Red (Degraded/Failed):** Problem requires immediate attention
- **Gray (Unknown):** Can't determine status

---

## UI Operations

### Viewing Application Details

1. **Click on any application card** to open the detailed view

2. You'll see the **Resource Tree** showing all Kubernetes resources:

```
┌─────────────────────────────────────────────────────────────────────┐
│  n8n-prod                                    [SYNC] [REFRESH] [...] │
├─────────────────────────────────────────────────────────────────────┤
│  APP HEALTH: Healthy    SYNC STATUS: Synced    REVISION: abc123    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Summary] [Parameters] [Manifest] [Diff] [Events] [Logs]          │
│                                                                     │
│  Resource Tree:                                                     │
│                                                                     │
│  📦 n8n-prod (Application)                                         │
│  ├── 📋 n8n (Deployment) ✓ Healthy                                 │
│  │   └── 🔄 n8n-xyz123 (ReplicaSet) ✓                              │
│  │       └── 🟢 n8n-xyz123-abc (Pod) ✓ Running                     │
│  ├── 🌐 n8n (Service) ✓                                            │
│  ├── 🔗 n8n (Ingress) ✓                                            │
│  ├── 💾 n8n-data (PersistentVolumeClaim) ✓                         │
│  ├── 🔑 n8n-secrets (Secret) ✓                                     │
│  └── 👤 n8n (ServiceAccount) ✓                                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

3. **Click any resource** in the tree to see its details

4. **Tabs available:**
   - **Summary:** Overview of the resource
   - **Manifest:** Live YAML from the cluster
   - **Desired Manifest:** YAML from Git
   - **Diff:** Side-by-side comparison
   - **Events:** Kubernetes events
   - **Logs:** Container logs (for pods)

---

### Syncing an Application

Syncing deploys the Git state to the cluster.

#### Method 1: Quick Sync (Single App)

1. From the **Applications Dashboard**, find your application card
2. Click the **circular arrow icon** (↻) on the card, OR
3. Click the card to open details, then click **"SYNC"** button (top right)

#### Method 2: Sync with Options

1. Click the application card to open details
2. Click **"SYNC"** button in the top-right corner
3. A sync panel slides out from the right:

```
┌──────────────────────────────────┐
│  Synchronize n8n-prod            │
├──────────────────────────────────┤
│                                  │
│  Revision: HEAD                  │
│  [Dropdown: HEAD/specific commit]│
│                                  │
│  ☐ PRUNE                         │
│    Delete resources not in Git   │
│                                  │
│  ☐ DRY RUN                       │
│    Preview without applying      │
│                                  │
│  ☐ APPLY ONLY                    │
│    Skip pre/post sync hooks      │
│                                  │
│  ☐ FORCE                         │
│    Overwrite cluster state       │
│                                  │
│  ─────────────────────────────── │
│  Sync Options:                   │
│  ☑ Auto-create namespace         │
│  ☐ Server-side apply             │
│  ☐ Replace                       │
│                                  │
│  [SYNCHRONIZE]  [Cancel]         │
│                                  │
└──────────────────────────────────┘
```

4. **Common scenarios:**

   | Scenario | Options to Select |
   |----------|-------------------|
   | Normal sync | Leave defaults, click SYNCHRONIZE |
   | Preview changes | Check "DRY RUN", click SYNCHRONIZE |
   | Force overwrite | Check "FORCE", click SYNCHRONIZE |
   | Clean up removed resources | Check "PRUNE", click SYNCHRONIZE |

5. Click **"SYNCHRONIZE"** to start

6. Watch the **sync progress** in the resource tree - resources will show spinning icons

#### Method 3: Sync Specific Resources Only

1. Open application details
2. In the resource tree, **select specific resources** by clicking them (hold Ctrl/Cmd for multiple)
3. Click **"SYNC"** button
4. Only selected resources will be listed in the sync panel
5. Click **"SYNCHRONIZE"**

---

### Refreshing an Application

Refreshing re-reads the Git repository without deploying.

1. Open the application details view
2. Click the **"REFRESH"** button (top-right, next to SYNC)
3. A dropdown appears:

```
┌─────────────────┐
│  Normal         │  ← Re-fetch from Git
│  Hard           │  ← Clear cache and re-fetch
└─────────────────┘
```

4. **Normal Refresh:** Use for routine checks
5. **Hard Refresh:** Use when ArgoCD seems out of sync or shows stale data

---

### Viewing Differences (Diff)

See what's different between Git and the cluster.

#### App-Level Diff

1. Open application details
2. Click the **"APP DIFF"** button (near top)
3. A modal shows all differences across all resources:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Application Diff                                          [Close] │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Deployment/n8n                                                     │
│  ─────────────────────────────────────────────────────────────────  │
│  - replicas: 1                                                      │
│  + replicas: 2                                                      │
│                                                                     │
│  ConfigMap/n8n-config                                               │
│  ─────────────────────────────────────────────────────────────────  │
│  (no changes)                                                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

#### Resource-Level Diff

1. Click a specific resource in the tree
2. Click the **"DIFF"** tab
3. See side-by-side comparison:
   - **Left (red):** Current cluster state
   - **Right (green):** Desired state from Git

---

### Viewing Logs

Access container logs directly from ArgoCD.

1. Open application details
2. In the resource tree, **click on a Pod** (🟢 icon)
3. Click the **"LOGS"** tab
4. You'll see the log viewer:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Logs: n8n-xyz123-abc                                              │
├─────────────────────────────────────────────────────────────────────┤
│  Container: [n8n        ▼]    [Download] [Wrap] [Follow]           │
├─────────────────────────────────────────────────────────────────────┤
│  2024-01-15T10:23:45Z Starting n8n...                              │
│  2024-01-15T10:23:46Z Connecting to database...                    │
│  2024-01-15T10:23:47Z Database connected                           │
│  2024-01-15T10:23:48Z Starting workflow engine...                  │
│  2024-01-15T10:23:49Z n8n ready on port 5678                       │
│  ...                                                                │
└─────────────────────────────────────────────────────────────────────┘
```

5. **Log controls:**
   - **Container dropdown:** Switch containers (if pod has multiple)
   - **Follow:** Auto-scroll to new logs (like `tail -f`)
   - **Wrap:** Wrap long lines
   - **Download:** Save logs to file
   - **Filter:** Search within logs

---

### Viewing Events

See Kubernetes events for troubleshooting.

1. Open application details
2. Click a resource in the tree
3. Click the **"EVENTS"** tab
4. See recent events:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Events: n8n (Deployment)                                          │
├─────────────────────────────────────────────────────────────────────┤
│  LAST SEEN  │  TYPE    │  REASON           │  MESSAGE              │
│  ───────────┼──────────┼───────────────────┼────────────────────── │
│  2m ago     │  Normal  │  ScalingReplicaSet│  Scaled up to 1       │
│  5m ago     │  Normal  │  ScalingReplicaSet│  Scaled down to 0     │
│  10m ago    │  Warning │  FailedScheduling │  Insufficient cpu     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Rolling Back an Application

Revert to a previous Git commit.

1. Open application details
2. Click the **"HISTORY AND ROLLBACK"** button (clock icon, top area)
3. You'll see deployment history:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Deployment History                                                 │
├─────────────────────────────────────────────────────────────────────┤
│  #  │  REVISION       │  DEPLOYED AT        │  DEPLOYED BY         │
│  ───┼─────────────────┼─────────────────────┼───────────────────── │
│  3  │  abc123 (HEAD)  │  2024-01-15 10:30   │  admin    [CURRENT]  │
│  2  │  def456         │  2024-01-14 15:20   │  admin    [Rollback] │
│  1  │  ghi789         │  2024-01-13 09:15   │  admin    [Rollback] │
└─────────────────────────────────────────────────────────────────────┘
```

4. Click **"Rollback"** next to the desired revision
5. Confirm the rollback
6. ArgoCD will sync to that specific commit

---

### Managing App Settings

#### Editing Application Parameters

For Helm apps, you can modify values:

1. Open application details
2. Click **"APP DETAILS"** (gear icon, top right)
3. Click the **"PARAMETERS"** tab
4. You'll see Helm values:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Parameters                                                         │
├─────────────────────────────────────────────────────────────────────┤
│  NAME                    │  VALUE                                   │
│  ────────────────────────┼───────────────────────────────────────── │
│  resources.limits.cpu    │  500m                      [Edit]        │
│  resources.limits.memory │  256Mi                     [Edit]        │
│  replicas                │  1                         [Edit]        │
└─────────────────────────────────────────────────────────────────────┘
```

5. Click **"Edit"** to modify values
6. **Note:** Changes here are temporary - they'll be overwritten on next Git sync

#### Viewing Source Info

1. Open application details
2. Click **"APP DETAILS"** (gear icon)
3. **"SUMMARY"** tab shows:
   - Source repository URL
   - Target revision (branch/tag/commit)
   - Path within repository
   - Destination cluster and namespace

---

### Deleting an Application

**Warning:** This can delete all resources managed by the app!

1. Open application details
2. Click **"DELETE"** button (trash icon, top right)
3. A confirmation dialog appears:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Delete Application                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Are you sure you want to delete 'n8n-prod'?                       │
│                                                                     │
│  ☐ Cascade - Delete all application resources                      │
│                                                                     │
│  Type application name to confirm: [____________]                   │
│                                                                     │
│  [DELETE]  [Cancel]                                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

4. **Cascade option:**
   - **Checked:** Deletes the app AND all Kubernetes resources it created
   - **Unchecked:** Only removes from ArgoCD, leaves resources running

5. Type the application name to confirm
6. Click **"DELETE"**

---

### Creating a New Application (UI)

1. Click **"+ NEW APP"** button (top left of dashboard)

2. Fill in the form:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Create Application                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  GENERAL                                                            │
│  ─────────────────────────────────────────────────────────────────  │
│  Application Name:  [my-new-app___________]                        │
│  Project:           [default_____________▼]                        │
│  Sync Policy:       ○ Manual  ● Automatic                          │
│                     ☑ Prune Resources                              │
│                     ☑ Self Heal                                    │
│                                                                     │
│  SOURCE                                                             │
│  ─────────────────────────────────────────────────────────────────  │
│  Repository URL:    [https://github.com/...]                       │
│  Revision:          [main___________________]                      │
│  Path:              [k8s/my-app_____________]                      │
│                                                                     │
│  DESTINATION                                                        │
│  ─────────────────────────────────────────────────────────────────  │
│  Cluster URL:       [https://kubernetes.default.svc▼]              │
│  Namespace:         [my-namespace___________]                      │
│                                                                     │
│  [CREATE]  [Cancel]                                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

3. **Recommended settings for this environment:**
   - Project: `default`
   - Sync Policy: `Automatic` with both Prune and Self Heal checked
   - Repository URL: `https://github.com/iius-rcox/II-n8n.git`
   - Revision: `main`
   - Cluster URL: `https://kubernetes.default.svc`

4. Click **"CREATE"**

5. The app will appear on the dashboard and begin syncing

**Note:** For consistency, prefer adding apps via Git (see Making Changes section below).

---

### Bulk Operations

#### Sync Multiple Apps

1. On the dashboard, click **"SYNC APPS"** (top toolbar)
2. Select apps to sync from the dropdown
3. Click **"SYNC"**

#### Refresh Multiple Apps

1. Click **"REFRESH APPS"** (top toolbar)
2. Select apps and refresh type (Normal/Hard)
3. Click **"REFRESH"**

---

### Filtering and Searching

#### Search Bar

- Top right of dashboard
- Type app name to filter visible apps
- Supports partial matches

#### Filter by Status

Click the filter icons in the toolbar:
- **Sync Status:** Synced / OutOfSync / Unknown
- **Health Status:** Healthy / Progressing / Degraded / Missing

#### Filter by Project/Cluster/Namespace

Use the dropdown filters in the toolbar to narrow down apps.

---

### Settings and User Management

Click the **gear icon** (⚙️) in the left sidebar.

#### Available Settings Pages:

| Page | Purpose |
|------|---------|
| **Repositories** | Manage Git repository connections |
| **Certificates** | TLS certificates for Git/Helm repos |
| **Clusters** | Connected Kubernetes clusters |
| **Projects** | ArgoCD projects (access control) |
| **Accounts** | User accounts and tokens |
| **Appearance** | UI theme (light/dark) |

---

## Troubleshooting in the UI

### App Shows "Unknown" Status

1. Click the app to open details
2. Look for error messages at the top
3. Try **Hard Refresh** (Refresh → Hard)
4. If persists, check the **Events** tab on resources
5. May need CLI intervention (see CLI section)

### App Shows "OutOfSync" but Nothing Changed

1. Open app details
2. Click **"APP DIFF"** to see differences
3. Often caused by:
   - Kubernetes adding default values
   - Timestamps/generation numbers changing
   - Resource ordering differences
4. If diff looks benign, just **Sync** to clear the status

### App Shows "Degraded" Health

1. Open app details
2. Look for **red resources** in the tree
3. Click the unhealthy resource
4. Check **Events** and **Logs** tabs
5. Common causes:
   - Image pull errors
   - Resource limits (OOM)
   - Failed health checks
   - Missing secrets/configmaps

### Sync Fails with Errors

1. After sync, check the **SYNC STATUS** area
2. Click **"SYNC FAILED"** to see error details
3. Common errors:
   - **"field is immutable"** - Use Force sync or delete resource manually
   - **"already exists"** - Resource was created outside ArgoCD
   - **"insufficient quota"** - Cluster resource limits

---

# Part 2: CLI Reference

## Getting the Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Check Application Status

```bash
# List all applications
kubectl get applications -n argocd

# Detailed status
kubectl get applications -n argocd -o wide

# Specific app details
kubectl get application n8n-prod -n argocd -o yaml

# Just sync and health status
kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

## Sync Operations

```bash
# Sync an application
kubectl patch application <app-name> -n argocd --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Force sync (overwrites cluster state)
kubectl patch application <app-name> -n argocd --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","syncStrategy":{"apply":{"force":true}}}}}'

# Sync with prune (delete removed resources)
kubectl patch application <app-name> -n argocd --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true}}}'
```

## Refresh Operations

```bash
# Normal refresh
kubectl annotate application <app-name> -n argocd argocd.argoproj.io/refresh=normal --overwrite

# Hard refresh (clear cache)
kubectl annotate application <app-name> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Sync Root App (All Applications)

```bash
kubectl annotate application root -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl patch application root -n argocd --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

## Check Sync Errors

```bash
# Get sync status message
kubectl get application <app-name> -n argocd -o jsonpath='{.status.operationState.message}'

# Get all conditions/errors
kubectl get application <app-name> -n argocd -o jsonpath='{.status.conditions[*].message}'

# View controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

## Restart ArgoCD Components

```bash
# Restart application controller (fixes sync issues)
kubectl rollout restart statefulset argocd-application-controller -n argocd

# Clear Redis cache (fixes stale data)
kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-redis

# Restart server (fixes UI issues)
kubectl rollout restart deployment argocd-server -n argocd
```

## Terminate Stuck Sync

```bash
# Cancel in-progress operation
kubectl patch application <app-name> -n argocd --type=merge -p '{"operation": null}'
```

## Delete CRD with Stuck Finalizers

```bash
kubectl patch crd <crd-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete crd <crd-name> --force --grace-period=0
```

---

# Part 3: Making Changes

## Updating n8n

n8n uses Kustomize from the `k8s/` directory.

1. Edit files in `k8s/deployment/` or `k8s/`
2. Commit and push to `main` branch
3. ArgoCD auto-syncs (or manually sync `n8n-prod`)

**Key files:**
- `k8s/deployment/n8n-deployment.yaml` - Deployment spec
- `k8s/kustomization.yaml` - Kustomize config

## Updating Helm Chart Versions

1. Edit `argocd/applications/<app>.yaml`
2. Change `targetRevision` to new version
3. Commit and push
4. Sync root, then sync the specific app

## Adding a New Application

1. Create `argocd/applications/<new-app>.yaml`
2. Add to `argocd/applications/kustomization.yaml`
3. Commit, push, and sync root

---

# Quick Reference Card

```
╔═══════════════════════════════════════════════════════════════════╗
║  ArgoCD Quick Reference - II-n8n Cluster                          ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  UI URL:        https://k8.ii-us.com                             ║
║  Username:      admin                                             ║
║  Git Repo:      https://github.com/iius-rcox/II-n8n.git          ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  GET PASSWORD                                                     ║
║  kubectl -n argocd get secret argocd-initial-admin-secret \      ║
║    -o jsonpath="{.data.password}" | base64 -d                    ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  CHECK STATUS                                                     ║
║  kubectl get applications -n argocd                               ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  SYNC AN APP                                                      ║
║  kubectl patch application <name> -n argocd --type=merge \       ║
║    -p '{"operation":{"initiatedBy":{"username":"admin"},         ║
║    "sync":{"revision":"HEAD"}}}'                                 ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  HARD REFRESH                                                     ║
║  kubectl annotate application <name> -n argocd \                 ║
║    argocd.argoproj.io/refresh=hard --overwrite                   ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  FIX STUCK/UNKNOWN STATUS                                         ║
║  kubectl rollout restart statefulset \                           ║
║    argocd-application-controller -n argocd                       ║
║  kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-redis ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
```
