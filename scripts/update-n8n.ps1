# update-n8n.ps1 - PowerShell version with rollback capability

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Configuration
$NAMESPACE = "n8n-prod"
$BACKUP_DIR = ".\backups"
$TIMEOUT = 600

# Show help
if ($Help) {
    Write-Host @"
Usage: .\update-n8n.ps1 [options]

Options:
  -Version <version>   Specify version to update to (e.g., 1.68.0)
  -DryRun             Show what would be updated without making changes
  -Help               Show this help message

Examples:
  .\update-n8n.ps1                    # Update to latest version
  .\update-n8n.ps1 -Version 1.68.0   # Update to specific version
  .\update-n8n.ps1 -DryRun           # Preview changes without applying
"@
    exit 0
}

# Color functions
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor Green
}

function Write-Warning-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] WARNING: $Message" -ForegroundColor Yellow
}

function Write-Error-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] ERROR: $Message" -ForegroundColor Red
}

# Create backup directory
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null

# Validate environment
function Test-Environment {
    Write-Log "Validating environment..."
    
    # Check kubectl access
    try {
        $null = kubectl cluster-info 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl is not configured or cluster is not accessible"
        }
    }
    catch {
        Write-Error-Log "kubectl is not configured or cluster is not accessible"
        exit 1
    }
    
    # Check if n8n deployment exists
    try {
        $null = kubectl get deployment n8n -n $NAMESPACE 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "n8n deployment not found"
        }
    }
    catch {
        Write-Error-Log "n8n deployment not found in namespace $NAMESPACE"
        exit 1
    }
    
    # Check pod status
    $podStatus = kubectl get pods -n $NAMESPACE -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($podStatus -ne "Running") {
        Write-Error-Log "n8n pod is not running. Current status: $podStatus"
        exit 1
    }
    
    Write-Log "Environment validation completed"
}

# Get version information
function Get-VersionInfo {
    Write-Log "Getting version information..."
    
    # Get current version
    $currentImage = kubectl get deployment n8n -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}'
    $script:CURRENT_VERSION = $currentImage.Split(':')[1]
    Write-Log "Current version: $CURRENT_VERSION"
    
    # Determine target version
    if ($Version) {
        $script:TARGET_VERSION = $Version
    }
    else {
        # Try to get latest version from GitHub
        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/n8n-io/n8n/releases/latest" -ErrorAction Stop
            $script:TARGET_VERSION = $release.tag_name.TrimStart('n8n@')
            Write-Log "Latest version: $TARGET_VERSION"
        }
        catch {
            Write-Warning-Log "Could not determine latest version from GitHub"
            $response = Read-Host "Enter version to update to (or press Enter for 'latest')"
            $script:TARGET_VERSION = if ([string]::IsNullOrWhiteSpace($response)) { "latest" } else { $response }
        }
    }
    
    # Check if already on target version
    if ($CURRENT_VERSION -eq $TARGET_VERSION) {
        Write-Log "Already running version $TARGET_VERSION"
        $response = Read-Host "Continue with update anyway? (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Log "Update cancelled by user"
            exit 0
        }
    }
}

# Create backup
function Backup-Configuration {
    Write-Log "Creating configuration backup..."
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:BACKUP_FILE = "$BACKUP_DIR\n8n-deployment-backup-$timestamp.yaml"
    
    try {
        kubectl get deployment n8n -n $NAMESPACE -o yaml | Out-File -FilePath $BACKUP_FILE -Encoding UTF8
        Write-Log "Configuration backed up to: $BACKUP_FILE"
    }
    catch {
        Write-Error-Log "Failed to backup deployment manifest"
        exit 1
    }
}

# Perform update
function Update-Deployment {
    Write-Log "Starting n8n update..."
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would update from $CURRENT_VERSION to $TARGET_VERSION"
        return
    }
    
    Write-Log "Updating n8n to version: $TARGET_VERSION"
    
    # Update deployment YAML file
    $deploymentFile = "k8s\deployment\n8n-deployment.yaml"
    
    if (-not (Test-Path $deploymentFile)) {
        Write-Error-Log "Deployment file not found: $deploymentFile"
        exit 1
    }
    
    # Read and update the file
    $content = Get-Content $deploymentFile -Raw
    $content = $content -replace 'image: n8nio/n8n:[\d\.]+', "image: n8nio/n8n:$TARGET_VERSION"
    $content | Set-Content $deploymentFile -NoNewline
    
    # Apply the updated deployment
    try {
        kubectl apply -f $deploymentFile
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl apply failed"
        }
        Write-Log "Deployment update applied"
    }
    catch {
        Write-Error-Log "Failed to apply updated deployment"
        exit 1
    }
}

# Verify update
function Test-Update {
    Write-Log "Verifying update..."
    
    if ($DryRun) {
        return $true
    }
    
    # Wait for rollout
    Write-Log "Waiting for rollout to complete (timeout: ${TIMEOUT}s)..."
    
    try {
        kubectl rollout status deployment/n8n -n $NAMESPACE --timeout="${TIMEOUT}s"
        if ($LASTEXITCODE -ne 0) {
            throw "Rollout failed"
        }
    }
    catch {
        Write-Error-Log "Rollout failed to complete within timeout"
        return $false
    }
    
    # Check pod status
    $podStatus = kubectl get pods -n $NAMESPACE -l app=n8n -o jsonpath='{.items[0].status.phase}'
    if ($podStatus -ne "Running") {
        Write-Error-Log "Pod is not running after update. Status: $podStatus"
        return $false
    }
    
    # Get updated version
    $updatedImage = kubectl get deployment n8n -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}'
    $updatedVersion = $updatedImage.Split(':')[1]
    Write-Log "Update verified. Running version: $updatedVersion"
    
    # Health check
    Write-Log "Performing health check..."
    Start-Sleep -Seconds 5
    
    try {
        $healthCheck = kubectl exec deployment/n8n -n $NAMESPACE -- wget -q -O- http://localhost:5678/healthz 2>$null
        if ($healthCheck -match '"status":"ok"' -or $healthCheck -match 'ok') {
            Write-Log "Health check passed"
            return $true
        }
        else {
            Write-Warning-Log "Health check response unexpected: $healthCheck"
            return $true  # Don't fail on health check alone
        }
    }
    catch {
        Write-Warning-Log "Health check failed - n8n may not be responding correctly"
        return $true  # Don't fail on health check alone
    }
}

# Rollback function
function Invoke-Rollback {
    Write-Warning-Log "Rolling back n8n deployment..."
    
    if (-not (Test-Path $BACKUP_FILE)) {
        Write-Error-Log "Backup file not found for rollback: $BACKUP_FILE"
        exit 1
    }
    
    try {
        kubectl apply -f $BACKUP_FILE
        if ($LASTEXITCODE -ne 0) {
            throw "kubectl apply failed during rollback"
        }
        
        Write-Log "Waiting for rollback to complete..."
        kubectl rollout status deployment/n8n -n $NAMESPACE --timeout="${TIMEOUT}s"
        
        Write-Log "Rollback completed"
    }
    catch {
        Write-Error-Log "Rollback failed: $_"
        exit 1
    }
}

# Cleanup old backups
function Remove-OldBackups {
    Write-Log "Cleaning up old backup files..."
    
    try {
        Get-ChildItem -Path $BACKUP_DIR -Filter "n8n-deployment-backup-*.yaml" | 
            Sort-Object LastWriteTime -Descending | 
            Select-Object -Skip 5 | 
            Remove-Item -Force
        
        Write-Log "Old backups cleaned up (kept last 5)"
    }
    catch {
        Write-Warning-Log "Failed to cleanup old backups: $_"
    }
}

# Main execution
function Main {
    Write-Log "Starting n8n maintenance update..."
    Write-Host ""
    
    try {
        Test-Environment
        Get-VersionInfo
        
        if ($DryRun) {
            Write-Log "=== DRY RUN MODE ==="
            Write-Log "Would update from $CURRENT_VERSION to $TARGET_VERSION"
            Write-Log "No changes will be made"
            exit 0
        }
        
        Backup-Configuration
        Update-Deployment
        
        # Verify update
        if (-not (Test-Update)) {
            Write-Warning-Log "Update verification failed. Initiating rollback..."
            Invoke-Rollback
            Write-Error-Log "Update failed and was rolled back"
            exit 1
        }
        
        Write-Host ""
        Write-Log "=== Update Completed Successfully ==="
        Write-Host "Updated from version: $CURRENT_VERSION" -ForegroundColor Cyan
        Write-Host "To version:           $TARGET_VERSION" -ForegroundColor Cyan
        Write-Host ""
        
        Remove-OldBackups
        
        Write-Log "Update process completed successfully!"
    }
    catch {
        Write-Error-Log "Update process failed: $_"
        exit 1
    }
}

# Run main function
Main