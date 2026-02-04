# II-n8n Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-12-16

## Active Technologies
- YAML (Kubernetes manifests), Bash (scripts) + ArgoCD, External Secrets Operator, Azure Key Vault CSI Driver, cert-manager, Azure Web App Routing ingress (002-argocd-ui-akv-secrets)
- Azure Key Vault (secrets), Azure Managed Disks (existing PVCs) (002-argocd-ui-akv-secrets)

- YAML (Kubernetes manifests), Bash (backup scripts) + ArgoCD, ArgoCD Image Updater, Kustomize, Azure CLI (001-n8n-prod-deployment)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for YAML (Kubernetes manifests), Bash (backup scripts)

## Code Style

YAML (Kubernetes manifests), Bash (backup scripts): Follow standard conventions

## Recent Changes
- 002-argocd-ui-akv-secrets: Added YAML (Kubernetes manifests), Bash (scripts) + ArgoCD, External Secrets Operator, Azure Key Vault CSI Driver, cert-manager, Azure Web App Routing ingress

- 001-n8n-prod-deployment: Added YAML (Kubernetes manifests), Bash (backup scripts) + ArgoCD, ArgoCD Image Updater, Kustomize, Azure CLI

<!-- MANUAL ADDITIONS START -->

## n8n Workflow Integration (Lessons Learned)

### Workflow: Claude Agent Orchestrator POC
- **ID**: `Anfqbp8bXJpPFFK7`
- **Webhook**: `https://n8n.ii-us.com/webhook/agent-run`
- **Purpose**: Orchestrates Claude Code CLI agent runs via kubectl exec

### Key Technical Lessons

#### Switch Node Configuration
- **Problem**: Switch node "rules" mode does NOT work correctly when configured via n8n API
- **Solution**: Use `mode: "expression"` with output index mapping instead:
  ```javascript
  // Expression that returns output index (0-3)
  ={{ {'success': 0, 'lease': 1, 'auth': 2}[$json.route] ?? 3 }}
  ```
- **Workaround**: Set a `route` string field in upstream Code nodes, then switch on that

#### Exit Code Handling Pattern
```
Exit 0  → Output 0 → Success Response (200)
Exit 23 → Output 1 → Retry Loop (30s wait, max 3 retries)
Exit 57 → Output 2 → Teams Alert + Auth Fail Response (503)
Other   → Output 3 → Teams Alert + Error Response (500)
```

#### Mock Mode for Testing
- Add `mock` and `mock_exit_code` parameters to webhook input
- Use Code node to simulate exit codes without kubectl:
  ```javascript
  const exitCode = data.mock_exit_code;
  let route = 'error';
  if (exitCode === 0) route = 'success';
  else if (exitCode === 23) route = 'lease';
  else if (exitCode === 57) route = 'auth';
  return [{json: {...data, exit_code: exitCode, route: route}}];
  ```

#### Teams Adaptive Cards
- Use `application/vnd.microsoft.card.adaptive` content type
- Webhook URL format: `https://iius1.webhook.office.com/webhookb2/...`
- Cards support FactSet for structured data display

### API Usage Notes
- n8n API auth can be intermittent - retry on `AUTHENTICATION_ERROR`
- `n8n_update_partial_workflow` requires `nodeId` not `name` for updates
- Switch node connections via API may create malformed `"0"` keys instead of `"main"` array
- Use `n8n_executions` with `mode: "error"` to debug failed executions

### Webhook API
```bash
# Test with mock mode
curl -X POST https://n8n.ii-us.com/webhook/agent-run \
  -H "Content-Type: application/json" \
  -d '{"ticket_id": "TEST-001", "mock": true, "mock_exit_code": 57}'

# Real execution (requires claude-agent deployment)
curl -X POST https://n8n.ii-us.com/webhook/agent-run \
  -H "Content-Type: application/json" \
  -d '{"ticket_id": "TICKET-001", "phase": "intake", "agent_name": "pm"}'
```

## Claude Agent POC Setup

### Architecture
```
[n8n Webhook] → [HTTP Request Node] → [claude-agent Service:80] → [HTTP Server:3000] → [Claude CLI]
```

### Quick Start
```bash
# Deploy all components
kubectl apply -k k8s/claude-agent/

# Create Claude session secret (from local machine with claude logged in)
kubectl create secret generic claude-session \
  --namespace claude-agent \
  --from-file=$HOME/.claude/

# Test via n8n webhook
curl -X POST https://n8n.ii-us.com/webhook/agent-run \
  -H "Content-Type: application/json" \
  -d '{"ticket_id": "TEST-001", "phase": "test", "agent_name": "pm"}'
```

### File Locations
- `k8s/claude-agent/namespace.yaml` - Namespace definition
- `k8s/claude-agent/deployment.yaml` - Pod with HTTP server wrapping Claude CLI
- `k8s/claude-agent/service.yaml` - ClusterIP service (port 80 → 3000)
- `k8s/claude-agent/rbac-n8n.yaml` - RBAC for n8n kubectl exec (future use)
- `k8s/claude-agent/networkpolicy-n8n-egress.yaml` - Allow n8n → claude-agent traffic
- `k8s/claude-agent/kustomization.yaml` - Kustomize manifest

## Kubernetes Lessons Learned (Claude Agent POC)

### 1. Secret Mounts are Read-Only
**Problem:** Claude CLI creates directories (`~/.claude/todos`, `~/.claude/debug`) at runtime, but secrets mount read-only.
```
Error: ENOENT: no such file or directory, mkdir '/home/node/.claude/todos'
```
**Solution:** Use init container to copy credentials to writable emptyDir:
```yaml
initContainers:
- name: init-claude
  command: ["cp", "/claude-creds/.credentials.json", "/home/node/.claude/"]
  volumeMounts:
  - name: claude-session-secret
    mountPath: /claude-creds
    readOnly: true
  - name: claude-home  # emptyDir
    mountPath: /home/node/.claude
```

### 2. Non-Root npm Global Install
**Problem:** Running as user 1000, `npm install -g` fails with EACCES on `/usr/local/lib/node_modules`
**Solution:** Configure user-local npm prefix:
```bash
mkdir -p /home/node/.npm-global
npm config set prefix '/home/node/.npm-global'
export PATH="/home/node/.npm-global/bin:$PATH"
npm install -g @anthropic-ai/claude-code
```
Add PATH to container env:
```yaml
env:
- name: PATH
  value: /home/node/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

### 3. Azure Policy Requirements
**Problem:** AKS with Azure Policy rejects pods missing security settings
**Required additions:**
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
```
Apply to ALL containers including init containers.

### 4. Node.js Child Process with Claude CLI
**Problem:** `execFile` and `spawn` return exit code 143 (SIGTERM) even though Claude CLI works via `kubectl exec`
**Solution:** Use `spawnSync` for synchronous execution:
```javascript
const { spawnSync } = require('child_process');
const result = spawnSync('/path/to/claude', ['-p', prompt, '--max-turns', '1'], {
  timeout: 300000,
  encoding: 'utf8'
});
// result.stdout contains Claude's response
```

### 5. n8n Network Policy Blocks Private IPs
**Problem:** n8n's network policy allows port 80/443 but EXCLUDES private IP ranges (10.0.0.0/8)
```yaml
# Existing n8n policy blocks this:
except:
- 10.0.0.0/8  # ClusterIP range!
```
**Solution:** Add explicit egress policy for claude-agent namespace:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-n8n-to-claude-agent
  namespace: n8n-prod
spec:
  podSelector:
    matchLabels:
      app: n8n
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: claude-agent
      podSelector:
        matchLabels:
          app: claude-code-agent
    ports:
    - protocol: TCP
      port: 3000
```

### 6. n8n Switch Node API Bug
**Problem:** Switch node "rules" mode routes ALL items to output 0 when configured via API
**Solution:** Use "expression" mode with explicit output index:
```javascript
// Returns 0 for mock=true, 1 for mock=false
={{ $json.mock === true ? 0 : 1 }}
```

### Debug Commands
```bash
# Check pod logs
kubectl logs -n claude-agent deploy/claude-code-agent --tail=20

# Test HTTP server health
kubectl exec -n claude-agent deploy/claude-code-agent -- \
  curl -s http://localhost:3000/health

# Test from n8n namespace (verify network policy)
kubectl exec -n n8n-prod deploy/n8n -- \
  node -e "require('http').get('http://claude-agent.claude-agent.svc.cluster.local/health',r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>console.log(d))})"

# Check n8n execution errors
# Use n8n MCP: n8n_executions(action='get', id='<exec_id>', mode='error')
```
## Employee Termination Agent

### Workflow Details
- **ID**: `IIHfhhXx8DSh0U5d`
- **Webhook**: `https://n8n.ii-us.com/webhook/terminate-employee`
- **Purpose**: Automates employee offboarding via Azure VM Run Command on DC01

### What It Does
1. Accepts employee ID via webhook
2. Connects to Microsoft Graph and Exchange Online (cert-based auth)
3. Finds user by employeeID in Active Directory
4. Removes all Microsoft 365 licenses
5. Converts mailbox to shared
6. Disables AD account
7. Moves user to Disabled Users OU
8. Triggers AD Sync
9. Sends Teams notification on success/failure

### Usage
```bash
# Dry run (no changes made)
curl -X POST https://n8n.ii-us.com/webhook/terminate-employee \
  -H "Content-Type: application/json" \
  -d '{"employee_id": "174362", "dry_run": true, "requester": "your-name"}'

# Actual termination
curl -X POST https://n8n.ii-us.com/webhook/terminate-employee \
  -H "Content-Type: application/json" \
  -d '{"employee_id": "174362", "requester": "your-name", "ticket_id": "HR-001"}'
```

### Secrets Configuration
- **n8n-termination-secrets** (K8s secret in n8n-prod): Contains `MS_GRAPH_CLIENT_SECRET`
- Secret is mounted as env var and accessed via n8n's `$env()` function
- Requires `N8N_EXTERNAL_ALLOWED_VARIABLES` to include `MS_GRAPH_CLIENT_SECRET`

### Key Technical Details
- Uses Azure VM Run Command API (not kubectl exec)
- PowerShell script runs on INSDAL9DC01 (Azure VM in RG_PROD)
- Certificate thumbprint: `DE0FF14C5EABA90BA328030A59662518A3673009`
- App registration: `73b82823-d860-4bf6-938b-74deabeebab7`

## Known Issues

### ESO v1 API Corruption (2026-01-30)
**Status**: Workaround in place, not blocking operations

**Problem**: An ExternalSecret (`n8n-secrets`) was somehow stored with `external-secrets.io/v1` API version, but the CRD only supports v1alpha1 and v1beta1. This causes the ESO operator to fail when listing ExternalSecrets:
```
Error from server: request to convert CR from an invalid group/version: external-secrets.io/v1
```

**Impact**:
- Cannot list ExternalSecrets with `kubectl get es`
- Cannot create new ExternalSecrets (they fail to sync)
- ESO operator logs show continuous conversion errors

**Workaround Applied**:
1. Removed owner reference from `n8n-secrets` K8s secret (prevents accidental deletion)
2. Removed ESO management labels from the secret
3. Created `n8n-termination-secrets` manually (not managed by ESO)
4. The corrupted ExternalSecret is orphaned and doesn't control any real resources

**To Fully Fix** (requires etcd access or cluster admin):
- Delete the corrupted resource directly from etcd, OR
- Wait for ESO version that adds v1 API support with proper conversion
<!-- MANUAL ADDITIONS END -->
