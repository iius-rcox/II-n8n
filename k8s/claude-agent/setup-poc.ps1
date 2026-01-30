# Claude Agent POC Setup Script
# Run from PowerShell on your local machine

param(
    [switch]$SkipSecretCreation,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "=== Claude Agent POC Setup ===" -ForegroundColor Cyan

# Step 1: Check prerequisites
Write-Host "`n[1/5] Checking prerequisites..." -ForegroundColor Yellow
$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectl) {
    Write-Error "kubectl not found. Please install kubectl first."
    exit 1
}

$claudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $claudeDir)) {
    Write-Error "Claude session directory not found at $claudeDir. Please run 'claude login' first."
    exit 1
}

Write-Host "  kubectl: OK" -ForegroundColor Green
Write-Host "  Claude session: OK ($claudeDir)" -ForegroundColor Green

# Step 2: Apply namespace and deployment
Write-Host "`n[2/5] Applying Kubernetes manifests..." -ForegroundColor Yellow
$manifestDir = $PSScriptRoot

if ($DryRun) {
    kubectl apply -k $manifestDir --dry-run=client
} else {
    kubectl apply -k $manifestDir
}

# Step 3: Create Claude session secret
if (-not $SkipSecretCreation) {
    Write-Host "`n[3/5] Creating Claude session secret..." -ForegroundColor Yellow

    # Check if secret exists
    $secretExists = kubectl get secret claude-session -n claude-agent --ignore-not-found
    if ($secretExists) {
        Write-Host "  Secret exists. Deleting and recreating..." -ForegroundColor Yellow
        if (-not $DryRun) {
            kubectl delete secret claude-session -n claude-agent
        }
    }

    # Create secret from .claude directory
    # Note: kubectl create secret --from-file works with directory
    $claudeFiles = Get-ChildItem $claudeDir -Force
    Write-Host "  Found $($claudeFiles.Count) files in $claudeDir" -ForegroundColor Gray

    if ($DryRun) {
        Write-Host "  [DRY-RUN] Would create secret from $claudeDir" -ForegroundColor Gray
    } else {
        # Use WSL if available for better compatibility, otherwise use kubectl directly
        $wsl = Get-Command wsl -ErrorAction SilentlyContinue
        if ($wsl) {
            $wslPath = $claudeDir -replace '\\', '/' -replace 'C:', '/mnt/c'
            wsl kubectl create secret generic claude-session --namespace claude-agent --from-file=$wslPath
        } else {
            # Direct kubectl - may have issues with Windows paths
            kubectl create secret generic claude-session --namespace claude-agent --from-file="$claudeDir\"
        }
    }
} else {
    Write-Host "`n[3/5] Skipping secret creation (--SkipSecretCreation)" -ForegroundColor Yellow
}

# Step 4: Wait for pod to be ready
Write-Host "`n[4/5] Waiting for pod to be ready..." -ForegroundColor Yellow
if (-not $DryRun) {
    kubectl rollout status deployment/claude-code-agent -n claude-agent --timeout=120s
}

# Step 5: Test Claude CLI
Write-Host "`n[5/5] Testing Claude CLI..." -ForegroundColor Yellow
if (-not $DryRun) {
    Write-Host "  Checking Claude version..." -ForegroundColor Gray
    kubectl exec -n claude-agent deploy/claude-code-agent -- claude --version

    Write-Host "`n  Running health check prompt..." -ForegroundColor Gray
    kubectl exec -n claude-agent deploy/claude-code-agent -- claude -p "Say 'POC health check successful'" --max-turns 1
}

Write-Host "`n=== POC Setup Complete ===" -ForegroundColor Green
Write-Host @"

Next steps:
1. Test the n8n workflow without mock mode:
   curl -X POST https://n8n.ii-us.com/webhook/agent-run \
     -H "Content-Type: application/json" \
     -d '{"ticket_id": "TEST-REAL", "phase": "intake", "agent_name": "pm"}'

2. If Claude auth fails (exit 57), refresh tokens:
   claude logout && claude login
   .\setup-poc.ps1  # Re-run this script

3. View pod logs:
   kubectl logs -n claude-agent deploy/claude-code-agent -f

"@ -ForegroundColor Cyan
