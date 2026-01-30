# Multi-Agent Development System — Implementation Plan v4.6.1 (II-US)

Production-ready implementation for I&I Soft Craft Solutions Azure environment using Claude Max subscription.

---

## Version History

| Version | Key Changes |
|---------|-------------|
| v4.0 - v4.5.3 | Core architecture, concurrency, hardening |
| v4.6.0 | Claude Max session tokens (no API key), II-US resource names |
| **v4.6.1** | HTTP wrapper for n8n (POC validated), init container pattern, Azure Policy compliance, Teams reauth prompting |

---

## Authentication Strategy

| Component | Method |
|-----------|--------|
| **Azure** | Workload Identity (managed identity + federated credential) |
| **GitHub** | GitHub App installation token |
| **Claude** | Max subscription session tokens (mounted from K8s secret) |
| **Teams** | Teams Workflows incoming webhook |

> **Assumption**: Claude Max session tokens have sufficient longevity for automated use. If tokens expire, manual refresh required (copy updated `~/.claude/` to K8s secret).

---

## II-US Azure Environment

### Existing Resources

| Resource | Value |
|----------|-------|
| **Subscription ID** | `a78954fe-f6fe-4279-8be0-2c748be2f266` |
| **Tenant ID** | `953922e6-5370-4a01-a3d5-773a30df726b` |
| **Resource Group** | `rg_prod` |
| **Region** | `southcentralus` |
| **AKS Cluster** | `dev-aks` |
| **Container Registry** | `iiusacr.azurecr.io` |
| **Key Vault** | `iius-akv` |

### Resources to Create

| Resource | Name | Purpose |
|----------|------|---------|
| Storage Account | `iiusagentstore` | Agent state and artifacts |
| Managed Identity | `claude-agent-identity` | Workload Identity |
| K8s Namespace | `claude-agent` | Agent workloads |
| K8s Service Account | `claude-agent-sa` | Identity binding |
| K8s Secret | `claude-session` | Claude Max tokens |
| K8s Secret | `github-app` | GitHub App credentials |
| K8s Secret | `teams-webhook` | Teams Workflow incoming webhook URL |

---

## Phase 1: Azure Infrastructure

### 1.1 Create Storage Account

```bash
RESOURCE_GROUP="rg_prod"
LOCATION="southcentralus"
STORAGE_ACCOUNT="iiusagentstore"

az storage account create   --name $STORAGE_ACCOUNT   --resource-group $RESOURCE_GROUP   --location $LOCATION   --sku Standard_LRS   --kind StorageV2   --allow-blob-public-access false

# Create containers
for container in agent-state agent-spec agent-plan agent-verification agent-review agent-release; do
  az storage container create     --account-name $STORAGE_ACCOUNT     --name $container     --auth-mode login
done
```

### 1.2 Create Managed Identity

```bash
IDENTITY_NAME="claude-agent-identity"

az identity create   --name $IDENTITY_NAME   --resource-group $RESOURCE_GROUP   --location $LOCATION

# Capture outputs
CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query clientId -o tsv)
OBJECT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)

echo "CLIENT_ID=$CLIENT_ID"  # Save this for K8s service account
```

### 1.3 Grant Storage Access

```bash
STORAGE_ID=$(az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query id -o tsv)

az role assignment create   --assignee $OBJECT_ID   --role "Storage Blob Data Contributor"   --scope $STORAGE_ID
```

### 1.4 Create Federated Credential

```bash
AKS_CLUSTER="dev-aks"

OIDC_ISSUER=$(az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP --query "oidcIssuerProfile.issuerUrl" -o tsv)

az identity federated-credential create   --name "claude-agent-fed-cred"   --identity-name $IDENTITY_NAME   --resource-group $RESOURCE_GROUP   --issuer "$OIDC_ISSUER"   --subject "system:serviceaccount:claude-agent:claude-agent-sa"   --audiences "api://AzureADTokenExchange"
```

---

## Phase 2: GitHub App

### 2.1 Create GitHub App

1. Go to: https://github.com/organizations/ii-us/settings/apps/new
2. Settings:
   - **Name**: `II-US Claude Agent`
   - **Homepage**: `https://ii-us.com`
   - **Webhook**: Uncheck "Active"
3. Permissions (Repository):
   - Contents: Read & Write
   - Pull requests: Read & Write
   - Issues: Read & Write
   - Metadata: Read-only
4. Create, note **App ID**, generate **Private Key**
5. Install on target repositories

### 2.2 Store in Key Vault (Optional)

```bash
az keyvault secret set --vault-name iius-akv --name "github-app-id" --value "YOUR_APP_ID"
az keyvault secret set --vault-name iius-akv --name "github-app-private-key" --file private-key.pem
```

---

## Phase 3: Capture Claude Session Tokens

### 3.1 On Your Machine (One-Time Setup)

```powershell
# PowerShell - Ensure fresh login
claude logout
claude login
# Complete OAuth in browser

# Verify working
claude -p "Say 'auth test successful'"

# Check contents
Get-ChildItem "$env:USERPROFILE\.claude" -Force
```

### 3.2 Create K8s Secret from Tokens

```bash
# From WSL or bash
kubectl create secret generic claude-session   --namespace claude-agent   --from-file=$HOME/.claude/   --dry-run=client -o yaml > claude-session-secret.yaml

kubectl apply -f claude-session-secret.yaml
```

### 3.3 Refresh Tokens (When Needed)

If tokens expire, repeat 3.1-3.2 to update the secret:

```bash
kubectl delete secret claude-session -n claude-agent
kubectl create secret generic claude-session --namespace claude-agent --from-file=$HOME/.claude/
kubectl rollout restart deployment/claude-code-agent -n claude-agent
```

---

## Phase 4: Docker Image

### 4.1 Dockerfile

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y     curl git jq bash coreutils ca-certificates gnupg nodejs npm     && rm -rf /var/lib/apt/lists/*

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg     | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg     && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"     | tee /etc/apt/sources.list.d/github-cli.list > /dev/null     && apt-get update && apt-get install -y gh     && rm -rf /var/lib/apt/lists/*

# yq
RUN curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64     -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Agent user
RUN useradd -m -s /bin/bash claude-agent     && mkdir -p /home/claude-agent/scripts /home/claude-agent/.claude /workspace/work     && chown -R claude-agent:claude-agent /home/claude-agent /workspace

COPY scripts/ /home/claude-agent/scripts/
RUN chmod +x /home/claude-agent/scripts/*.sh

USER claude-agent
WORKDIR /workspace

ENV STORAGE_ACCOUNT=iiusagentstore
ENV HOME=/home/claude-agent
```

### 4.2 Build and Push

```bash
az acr login --name iiusacr
docker build -t iiusacr.azurecr.io/claude-agent:v4.6.1 .
docker push iiusacr.azurecr.io/claude-agent:v4.6.1
```

---

## Phase 5: Kubernetes Deployment

### 5.1 Namespace and Service Account

```yaml
# claude-agent-ns.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: claude-agent
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: claude-agent-sa
  namespace: claude-agent
  annotations:
    azure.workload.identity/client-id: "<CLIENT_ID_FROM_STEP_1.2>"
  labels:
    azure.workload.identity/use: "true"
```

### 5.2 GitHub Secret

```yaml
# github-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-app
  namespace: claude-agent
type: Opaque
stringData:
  app-id: "YOUR_GITHUB_APP_ID"
  private-key.pem: |
    -----BEGIN RSA PRIVATE KEY-----
    YOUR_PRIVATE_KEY_HERE
    -----END RSA PRIVATE KEY-----
```

### 5.3 Teams Webhook Secret

Create a Teams Workflow “incoming webhook” that posts to your chosen chat/channel and copy the webhook URL.

```bash
kubectl create secret generic teams-webhook   -n claude-agent   --from-literal=url='https://YOUR_TEAMS_WORKFLOW_WEBHOOK_URL'   --dry-run=client -o yaml > teams-webhook-secret.yaml

kubectl apply -f teams-webhook-secret.yaml
```

### 5.4 Deployment (Updated for v4.6.1)

> **POC Lesson**: Kubernetes secrets are mounted read-only, but Claude CLI needs to write to `~/.claude/` at runtime. Use an init container to copy credentials to a writable `emptyDir` volume.

> **Azure Policy Requirement**: AKS with Azure Policy typically requires `seccompProfile: RuntimeDefault` and explicit resource requests on **all** containers (including init containers).

```yaml
# claude-agent-deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: claude-code-agent
  namespace: claude-agent
  labels:
    app: claude-code-agent
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: claude-code-agent
  template:
    metadata:
      labels:
        app: claude-code-agent
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: claude-agent-sa

      # Pod-level defaults to satisfy common Azure Policy / PSS restrictions
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      initContainers:
      - name: init-claude
        image: iiusacr.azurecr.io/claude-agent:v4.6.1
        command: ["/bin/bash","-lc"]
        args:
          - |
            set -euo pipefail
            mkdir -p /home/claude-agent/.claude
            # Copy all files from the read-only secret into the writable emptyDir.
            # (The secret is created from ~/.claude/, so filenames may vary.)
            if [ -d /claude-creds ] && [ "$(ls -A /claude-creds 2>/dev/null || true)" != "" ]; then
              cp -a /claude-creds/. /home/claude-agent/.claude/
              echo "Claude session files copied into writable volume."
            else
              echo "No Claude session files found in secret. Claude CLI will require authentication."
            fi
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: claude-session-secret
          mountPath: /claude-creds
          readOnly: true
        - name: claude-home
          mountPath: /home/claude-agent/.claude

      containers:
      - name: agent
        image: iiusacr.azurecr.io/claude-agent:v4.6.1
        command: ["sleep", "infinity"]
        env:
        - name: HOME
          value: /home/claude-agent
        - name: STORAGE_ACCOUNT
          value: "iiusagentstore"
        - name: TEAMS_WEBHOOK_URL
          valueFrom:
            secretKeyRef:
              name: teams-webhook
              key: url
        volumeMounts:
        - name: claude-home
          mountPath: /home/claude-agent/.claude
        - name: github-creds
          mountPath: /secrets/github
          readOnly: true
        - name: workspace
          mountPath: /workspace
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "8Gi"
            cpu: "4"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]

      volumes:
      - name: claude-session-secret
        secret:
          secretName: claude-session
          optional: true
      - name: claude-home
        emptyDir:
          sizeLimit: 1Gi
      - name: github-creds
        secret:
          secretName: github-app
      - name: workspace
        emptyDir:
          sizeLimit: 10Gi
```

### 5.5 Deploy

```bash
az aks get-credentials --resource-group rg_prod --name dev-aks

kubectl apply -f claude-agent-ns.yaml
kubectl apply -f github-secret.yaml
kubectl apply -f teams-webhook-secret.yaml
kubectl apply -f claude-agent-deploy.yaml

kubectl get pods -n claude-agent
```

### 5.6 HTTP Wrapper for n8n Integration

> **POC Lesson**: n8n doesn't have kubectl installed, and even if it did, `kubectl exec` uses WebSocket upgrades that are harder to debug than simple HTTP. The HTTP wrapper approach is more maintainable and keeps n8n vanilla.

> **Important**: Use `spawnSync` (not async methods like `execFile`/`spawn`) — async methods may return exit code 143 (SIGTERM) when the HTTP response completes before the child process.

#### Agent Deployment Change (Alternative to sleep infinity)

For n8n integration, replace `command: ["sleep", "infinity"]` with an HTTP server:

```yaml
# In claude-agent-deploy.yaml, replace the agent container command:
containers:
- name: agent
  image: iiusacr.azurecr.io/claude-agent:v4.6.1
  command: ["/bin/bash","-lc"]
  args:
    - |
      node /home/claude-agent/scripts/http-server.js
  ports:
  - containerPort: 3000
    name: http
  livenessProbe:
    httpGet:
      path: /health
      port: 3000
    initialDelaySeconds: 60
    periodSeconds: 30
  readinessProbe:
    httpGet:
      path: /health
      port: 3000
    initialDelaySeconds: 30
    periodSeconds: 10
  # ... rest of container spec unchanged ...
```

#### scripts/http-server.js

```javascript
const http = require('http');
const { spawnSync } = require('child_process');

const PORT = 3000;
const CLAUDE_PATH = '/usr/local/bin/claude';

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }));
    return;
  }

  if (req.method === 'POST' && req.url === '/run') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const { prompt, max_turns = 1, timeout = 300 } = JSON.parse(body);
        if (!prompt) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'prompt is required' }));
          return;
        }

        console.log(`[${new Date().toISOString()}] Running prompt: ${prompt.substring(0, 50)}...`);

        const args = ['-p', prompt, '--max-turns', String(max_turns)];
        const result = spawnSync(CLAUDE_PATH, args, {
          timeout: timeout * 1000,
          maxBuffer: 10 * 1024 * 1024,
          encoding: 'utf8',
          env: process.env
        });

        const exitCode = result.status ?? 1;

        res.writeHead(exitCode === 0 ? 200 : 500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          exit_code: exitCode,
          stdout: (result.stdout || '').trim(),
          stderr: (result.stderr || '').trim(),
          timestamp: new Date().toISOString()
        }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON: ' + e.message }));
      }
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Claude Agent HTTP server listening on port ${PORT}`);
});
```

#### Service for n8n Access

```yaml
# claude-agent-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: claude-agent
  namespace: claude-agent
  labels:
    app: claude-code-agent
spec:
  type: ClusterIP
  selector:
    app: claude-code-agent
  ports:
  - port: 80
    targetPort: 3000
    name: http
```

#### n8n HTTP Request Node Configuration

```
URL: http://claude-agent.claude-agent.svc.cluster.local/run
Method: POST
Body (JSON):
{
  "prompt": "{{ $json.prompt }}",
  "max_turns": 1,
  "timeout": 300
}
```

### 5.7 Network Policy for n8n

> **POC Lesson**: If n8n has a restrictive egress NetworkPolicy that blocks private IPs (10.0.0.0/8), it will also block ClusterIP services. Add an explicit allow rule.

Only apply this if n8n's existing network policy blocks egress to private IPs:

```yaml
# networkpolicy-n8n-egress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-n8n-to-claude-agent
  namespace: n8n-prod  # Adjust to your n8n namespace
  labels:
    app: n8n
spec:
  podSelector:
    matchLabels:
      app: n8n
  policyTypes:
  - Egress
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
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: claude-agent
    ports:
    - protocol: TCP
      port: 80
```

#### n8n Switch Node Note

> **n8n API Bug**: When configuring Switch nodes via n8n API, use `mode: "expression"` instead of `mode: "rules"`. The rules mode has a bug where all items route to output 0 regardless of conditions.
>
> Expression mode example: `{{ $json.mock === true ? 0 : 1 }}`

---

## Phase 6: Verify

### 6.1 Azure Auth

```bash
kubectl exec -it -n claude-agent deploy/claude-code-agent -- bash

az login --identity --allow-no-subscriptions
az storage container list --account-name iiusagentstore --auth-mode login -o table
```

### 6.2 Claude Auth

```bash
claude -p "Say 'Claude Max auth working'"
```

### 6.3 GitHub Auth

```bash
export GITHUB_PRIVATE_KEY_FILE="/secrets/github/private-key.pem"
source /home/claude-agent/scripts/mint-github-token.sh
gh auth status
```

---

## Phase 7: Teams Prompting for Claude Reauthentication

Goal: when Claude Max session tokens expire, automatically post a Teams message that instructs you to reauthenticate locally and refresh the `claude-session` secret.

### 7.1 Create Teams Workflow Incoming Webhook

Create a Teams Workflow that:
- Uses the “When a Teams webhook request is received” trigger
- Posts to a target chat/channel (recommended: dedicated Ops channel or 1:1 chat)
- Uses “Post card in chat or channel”

Copy the resulting webhook URL and store it in the `teams-webhook` secret (Phase 5.3).

### 7.2 Add Scripts

#### scripts/notify-teams.sh

```bash
#!/bin/bash
# Post a notification to Teams via Teams Workflows incoming webhook
# Env:
#   TEAMS_WEBHOOK_URL (required)
# Args:
#   1: title
#   2: message (markdown/plain text)
#   3: optional facts JSON (e.g. {"ticket":"TICKET-001","pod":"..."}), defaults to {}
set -euo pipefail

TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:?required}"

TITLE="${1:-Claude reauthentication required}"
MESSAGE="${2:-Claude session tokens appear expired. Please reauthenticate and update the claude-session secret.}"
FACTS_JSON="${3:-{}}"

if ! echo "$FACTS_JSON" | jq -e 'type=="object"' >/dev/null 2>&1; then
  echo "ERROR: FACTS_JSON must be a JSON object" >&2
  exit 1
fi

payload="$(jq -n   --arg title "$TITLE"   --arg message "$MESSAGE"   --argjson facts "$FACTS_JSON"   '{
    "type": "message",
    "attachments": [
      {
        "contentType": "application/vnd.microsoft.card.adaptive",
        "content": {
          "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
          "type": "AdaptiveCard",
          "version": "1.4",
          "body": (
            [
              { "type": "TextBlock", "text": $title, "weight": "Bolder", "size": "Large", "wrap": true },
              { "type": "TextBlock", "text": $message, "wrap": true }
            ]
            + (
              (facts | to_entries | length) as $n
              | if $n > 0 then
                  [
                    { "type": "TextBlock", "text": "Context", "weight": "Bolder", "spacing": "Medium" },
                    {
                      "type": "FactSet",
                      "facts": (facts | to_entries | map({ "title": (.key + ":"), "value": (.value|tostring) }))
                    }
                  ]
                else
                  []
                end
            )
            + [
              { "type": "TextBlock", "text": "Reauth steps (local machine):", "weight": "Bolder", "spacing": "Medium" },
              { "type": "TextBlock", "wrap": true, "text":
"1) claude logout && claude login\n2) kubectl delete secret claude-session -n claude-agent\n3) kubectl create secret generic claude-session -n claude-agent --from-file=$HOME/.claude/\n4) kubectl rollout restart deployment/claude-code-agent -n claude-agent"
              }
            ]
          )
        }
      }
    ]
  }')"

curl -fsS -X POST   -H "Content-Type: application/json"   -d "$payload"   "$TEAMS_WEBHOOK_URL" >/dev/null
```

#### scripts/claude-auth-check.sh

```bash
#!/bin/bash
# Verifies Claude Max session tokens are valid by running a cheap prompt.
# On failure, optionally notifies Teams and exits with a distinct code.
# Env:
#   NOTIFY_TEAMS_ON_FAIL=true|false (default true)
#   TEAMS_WEBHOOK_URL (required if NOTIFY_TEAMS_ON_FAIL=true)
# Args:
#   1: optional ticket id (or "none")
#   2: optional agent name (or "none")
set -euo pipefail

NOTIFY="${NOTIFY_TEAMS_ON_FAIL:-true}"
TICKET_ID="${1:-none}"
AGENT_NAME="${2:-none}"

if claude -p "health check" >/dev/null 2>&1; then
  exit 0
fi

echo "ERROR: Claude auth failed - session tokens may be expired" >&2

if [[ "$NOTIFY" == "true" ]]; then
  TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:?required}"

  POD_NAME="${HOSTNAME:-unknown}"
  FACTS="$(jq -n     --arg ticket "$TICKET_ID"     --arg agent "$AGENT_NAME"     --arg pod "$POD_NAME"     '{ticket:$ticket, agent:$agent, pod:$pod}')"

  /home/claude-agent/scripts/notify-teams.sh     "Claude reauthentication required"     "Claude CLI health check failed inside AKS. The mounted Claude Max session tokens are likely expired.\n\nPlease reauthenticate locally and refresh the K8s claude-session secret."     "$FACTS" || true
fi

# Distinct exit code for token expiry / auth failure
exit 57
```

### 7.3 Proactive Watchdog CronJob

This posts the Teams prompt even if no agent run is happening.

```yaml
# claude-auth-watchdog.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: claude-auth-watchdog
  namespace: claude-agent
spec:
  schedule: "*/30 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        metadata:
          labels:
            app: claude-auth-watchdog
            azure.workload.identity/use: "true"
        spec:
          serviceAccountName: claude-agent-sa
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
            seccompProfile:
              type: RuntimeDefault
          initContainers:
          - name: init-claude
            image: iiusacr.azurecr.io/claude-agent:v4.6.1
            command: ["/bin/bash","-lc"]
            args:
              - |
                set -euo pipefail
                mkdir -p /home/claude-agent/.claude
                if [ -d /claude-creds ] && [ "$(ls -A /claude-creds 2>/dev/null || true)" != "" ]; then
                  cp -a /claude-creds/. /home/claude-agent/.claude/
                fi
            resources:
              requests:
                memory: "32Mi"
                cpu: "25m"
              limits:
                memory: "64Mi"
                cpu: "50m"
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop: ["ALL"]
            volumeMounts:
            - name: claude-session-secret
              mountPath: /claude-creds
              readOnly: true
            - name: claude-home
              mountPath: /home/claude-agent/.claude
          containers:
          - name: watchdog
            image: iiusacr.azurecr.io/claude-agent:v4.6.1
            command: ["/bin/bash","-lc"]
            args:
              - |
                set -euo pipefail
                export NOTIFY_TEAMS_ON_FAIL=true
                /home/claude-agent/scripts/claude-auth-check.sh "none" "watchdog"
            env:
            - name: TEAMS_WEBHOOK_URL
              valueFrom:
                secretKeyRef:
                  name: teams-webhook
                  key: url
            resources:
              requests:
                memory: "64Mi"
                cpu: "50m"
              limits:
                memory: "128Mi"
                cpu: "100m"
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop: ["ALL"]
            volumeMounts:
            - name: claude-home
              mountPath: /home/claude-agent/.claude
          volumes:
          - name: claude-session-secret
            secret:
              secretName: claude-session
              optional: true
          - name: claude-home
            emptyDir:
              sizeLimit: 256Mi
```

Apply it:

```bash
kubectl apply -f claude-auth-watchdog.yaml
kubectl get cronjobs -n claude-agent
kubectl get jobs -n claude-agent --sort-by=.metadata.creationTimestamp
```

---

## Scripts

All scripts in `/home/claude-agent/scripts/`.

See v4.5.3 for full script contents. New/updated for v4.6.1:

- `http-server.js` (new, for n8n HTTP integration)
- `notify-teams.sh` (new)
- `claude-auth-check.sh` (new)

### run-agent.sh (Updated Section)

Add this **before acquiring the lease** (fail-fast; do not hold a lease while waiting for human action):

```bash
/home/claude-agent/scripts/claude-auth-check.sh "$TICKET_ID" "$AGENT_NAME"
```

---

## Exit Codes

| Code | Cause | n8n Action |
|------|-------|------------|
| 0 | Success | Continue |
| 1 | General error | Alert |
| 23 | Lease held | Retry with backoff |
| 40 | Unexpected output files | Alert |
| 41 | Missing required output/field | Alert |
| 42 | Lease lost during execution | Retry |
| 57 | Claude tokens expired / auth failure | Notify + pause (manual reauth) |
| 124 | Timeout | Alert |

---

## Quick Reference

### Run Agent (kubectl exec - debugging)

```bash
kubectl exec -n claude-agent deploy/claude-code-agent --   /home/claude-agent/scripts/run-agent.sh   TICKET-001 pm intake agent-spec 3600
```

### Run Agent (HTTP - n8n integration)

```bash
curl -X POST http://claude-agent.claude-agent.svc.cluster.local/run   -H "Content-Type: application/json"   -d '{"prompt": "Say hello", "max_turns": 1, "timeout": 300}'

curl http://claude-agent.claude-agent.svc.cluster.local/health
```

### Refresh Claude Tokens

```bash
claude logout && claude login

kubectl delete secret claude-session -n claude-agent
kubectl create secret generic claude-session -n claude-agent --from-file=$HOME/.claude/
kubectl rollout restart deployment/claude-code-agent -n claude-agent
```

### Break Stuck Lease

```bash
az storage blob lease break   --account-name iiusagentstore   --container-name agent-state   --blob-name TICKET-001/task-envelope.yml   --auth-mode login
```

---

## Checklist

### Azure (Phase 1)
- [ ] Create storage account `iiusagentstore`
- [ ] Create 6 blob containers
- [ ] Create managed identity `claude-agent-identity`
- [ ] Grant Storage Blob Data Contributor
- [ ] Create federated credential
- [ ] Note CLIENT_ID for K8s service account

### GitHub (Phase 2)
- [ ] Create GitHub App in ii-us org
- [ ] Note App ID
- [ ] Generate and save private key
- [ ] Install app on target repos

### Claude (Phase 3)
- [ ] Fresh `claude login` on your machine
- [ ] Create K8s secret from `~/.claude/`

### Teams Prompting (Phase 7)
- [ ] Create Teams Workflow incoming webhook
- [ ] Store webhook URL as `teams-webhook` secret
- [ ] Ensure deployment has `TEAMS_WEBHOOK_URL` env var
- [ ] Deploy `claude-auth-watchdog` CronJob
- [ ] Validate you receive Teams prompt when tokens are invalid

### Docker (Phase 4)
- [ ] Build image
- [ ] Push to iiusacr

### Kubernetes (Phase 5)
- [ ] Create namespace
- [ ] Create service account with CLIENT_ID annotation
- [ ] Create github-app secret
- [ ] Apply claude-session secret
- [ ] Apply teams-webhook secret
- [ ] Deploy agent pod (with init container for writable .claude)
- [ ] Verify seccompProfile: RuntimeDefault on all containers
- [ ] Verify resource requests on init containers (Azure Policy)
- [ ] Apply watchdog CronJob

### n8n Integration (Phase 5.6-5.7)
- [ ] Add http-server.js to agent image (or mount it)
- [ ] Deploy ClusterIP Service for claude-agent
- [ ] Apply NetworkPolicy for n8n egress (if n8n has restrictive policy)
- [ ] Configure n8n HTTP Request node to call claude-agent service
- [ ] Test end-to-end: n8n webhook → HTTP Request → Claude agent

### Verify (Phase 6)
- [ ] Azure Workload Identity works
- [ ] Claude commands work
- [ ] GitHub auth works
- [ ] End-to-end agent test passes

---

*Version: 4.6.1*  
*Environment: II-US Production (rg_prod / dev-aks)*  
*Auth: Claude Max + Workload Identity + GitHub App + Teams reauth prompting*  
*n8n Integration: HTTP wrapper (POC validated January 2026)*
