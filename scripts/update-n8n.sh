#!/bin/bash
# update-n8n.sh - Improved version with rollback capability

set -euo pipefail

# Configuration
NAMESPACE="n8n-prod"
BACKUP_DIR="./backups"
TIMEOUT="600s"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Pre-update validation
validate_environment() {
    log "Validating environment..."
    
    # Check if n8n is installed
    if ! kubectl get deployment n8n -n "$NAMESPACE" &> /dev/null; then
        error "n8n deployment not found in namespace $NAMESPACE"
    fi
    
    # Check if deployment is healthy
    local pod_status
    pod_status=$(kubectl get pods -n "$NAMESPACE" -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ "$pod_status" != "Running" ]; then
        error "n8n pod is not running. Current status: $pod_status"
    fi
    
    log "Environment validation completed"
}

# Get version information
get_versions() {
    log "Getting version information..."
    
    # Get current version from deployment
    CURRENT_VERSION=$(kubectl get deployment n8n -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d':' -f2)
    log "Current version: $CURRENT_VERSION"
    
    # Get latest version from GitHub API with error handling
    if command -v jq &> /dev/null; then
        LATEST_VERSION=$(curl -s -f "https://api.github.com/repos/n8n-io/n8n/releases/latest" | jq -r '.tag_name' 2>/dev/null || echo "unknown")
    else
        warn "jq not found, cannot determine latest version automatically"
        LATEST_VERSION="unknown"
    fi
    
    if [ "$LATEST_VERSION" != "unknown" ]; then
        log "Latest version: $LATEST_VERSION"
        
        # Compare versions (basic string comparison)
        if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
            log "Already running the latest version"
            read -p "Do you want to continue with the update anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Update cancelled by user"
                exit 0
            fi
        fi
    else
        warn "Could not determine latest version. You can specify a version manually."
        read -p "Enter the version to update to (or press Enter to use 'latest'): " LATEST_VERSION
        LATEST_VERSION=${LATEST_VERSION:-latest}
    fi
}

# Create backup of current configuration
backup_configuration() {
    log "Creating configuration backup..."
    
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/n8n-deployment-backup-$backup_timestamp.yaml"
    
    # Backup current deployment manifest
    kubectl get deployment n8n -n "$NAMESPACE" -o yaml > "$backup_file" || error "Failed to backup deployment manifest"
    
    log "Configuration backed up to: $backup_file"
    
    # Store backup file path for potential rollback
    export BACKUP_FILE="$backup_file"
}

# Perform the update
perform_update() {
    log "Starting n8n update..."
    
    # Update the deployment with new image
    log "Updating n8n to version: $LATEST_VERSION"
    
    if [ "$LATEST_VERSION" != "latest" ]; then
        # Update the deployment manifest with new image
        sed -i "s|image: n8nio/n8n:.*|image: n8nio/n8n:$LATEST_VERSION|" k8s/deployment/n8n-deployment.yaml
    fi
    
    # Apply the updated deployment
    kubectl apply -f k8s/deployment/n8n-deployment.yaml || error "Failed to apply updated deployment"
    
    log "Deployment update completed"
}

# Verify the update
verify_update() {
    log "Verifying update..."
    
    # Wait for rollout to complete
    log "Waiting for rollout to complete..."
    if ! kubectl rollout status deployment/n8n -n "$NAMESPACE" --timeout="$TIMEOUT"; then
        error "Rollout failed to complete within timeout"
    fi
    
    # Check pod status
    local pod_status
    pod_status=$(kubectl get pods -n "$NAMESPACE" -l app=n8n -o jsonpath='{.items[0].status.phase}')
    if [ "$pod_status" != "Running" ]; then
        error "Pod is not running after update. Status: $pod_status"
    fi
    
    # Get updated version
    local updated_version
    updated_version=$(kubectl get deployment n8n -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d':' -f2)
    log "Update verified. Running version: $updated_version"
    
    # Basic health check
    log "Performing health check..."
    if ! kubectl exec deployment/n8n -n "$NAMESPACE" -- wget -q --spider http://localhost:5678/healthz; then
        warn "Health check failed - n8n may not be responding correctly"
        return 1
    fi
    
    log "Health check passed"
    return 0
}

# Rollback function
rollback() {
    warn "Rolling back n8n deployment..."
    
    if [ -f "$BACKUP_FILE" ]; then
        kubectl apply -f "$BACKUP_FILE" || error "Rollback failed"
    else
        error "Backup file not found for rollback"
    fi
    
    log "Waiting for rollback to complete..."
    kubectl rollout status deployment/n8n -n "$NAMESPACE" --timeout="$TIMEOUT"
    
    log "Rollback completed"
}

# Main update process
main() {
    log "Starting n8n maintenance update..."
    
    # Trap to handle failures
    trap 'error "Update process failed"' ERR
    
    validate_environment
    get_versions
    backup_configuration
    perform_update
    
    # Verify update and rollback if necessary
    if ! verify_update; then
        warn "Update verification failed. Initiating rollback..."
        rollback
        error "Update failed and was rolled back"
    fi
    
    log "Update completed successfully!"
    log "Updated from $CURRENT_VERSION to $LATEST_VERSION"
    
    # Cleanup old backups (keep last 5)
    log "Cleaning up old backup files..."
    ls -t "$BACKUP_DIR"/n8n-deployment-backup-*.yaml 2>/dev/null | tail -n +6 | xargs -r rm
    
    log "Update process completed successfully!"
}

# Handle command line options
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [--dry-run] [--version VERSION]"
        echo "  --dry-run    Show what would be updated without making changes"
        echo "  --version    Specify version to update to"
        echo "  --help       Show this help message"
        exit 0
        ;;
    "--dry-run")
        log "Dry run mode - no changes will be made"
        validate_environment
        get_versions
        log "Dry run completed. Would update from $CURRENT_VERSION to $LATEST_VERSION"
        exit 0
        ;;
    "--version")
        LATEST_VERSION="$2"
        shift 2
        ;;
    "")
        ;;
    *)
        error "Unknown option: $1. Use --help for usage information."
        ;;
esac

# Run main function
main "$@"
