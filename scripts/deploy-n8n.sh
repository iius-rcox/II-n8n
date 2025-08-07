#!/bin/bash
# deploy-n8n.sh - Improved version with proper error handling and validation

set -euo pipefail

# Configuration
NAMESPACE="n8n-prod"
STORAGE_SIZE="20Gi"
TIMEOUT="600s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Pre-flight checks
preflight_checks() {
    log "Running pre-flight checks..."
    
    # Check kubectl access
    if ! kubectl cluster-info &> /dev/null; then
        error "kubectl is not configured or cluster is not accessible"
    fi
    
    # Check Helm installation
    if ! command -v helm &> /dev/null; then
        error "Helm is not installed"
    fi
    
    # Validate required files exist
    local required_files=(
        "k8s/namespace.yaml"
        "k8s/rbac/service-account.yaml" 
        "k8s/storage/pvc.yaml"
        "k8s/deployment/n8n-deployment.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "Required file not found: $file"
        fi
    done
    
    # Check if secrets file exists and warn if it contains default values
    if [ -f "k8s/secrets/n8n-secrets.yaml" ]; then
        if grep -q "your-encryption-key" "k8s/secrets/n8n-secrets.yaml"; then
            warn "Default encryption key detected in secrets file. Please update with a strong key."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        error "Secrets file not found: k8s/secrets/n8n-secrets.yaml"
    fi
    
    log "Pre-flight checks completed"
}

# Deploy infrastructure
deploy_infrastructure() {
    log "Deploying infrastructure components..."
    
    # Create namespace
    log "Creating namespace..."
    kubectl apply -f k8s/namespace.yaml
    
    # Create RBAC
    log "Setting up RBAC..."
    kubectl apply -f k8s/rbac/service-account.yaml
    
    # Create backup service account
    if [ -f "k8s/rbac/backup-service-account.yaml" ]; then
        log "Setting up backup service account..."
        kubectl apply -f k8s/rbac/backup-service-account.yaml
    fi
    
    # Create secrets (if exists)
    if [ -f "k8s/secrets/n8n-secrets.yaml" ]; then
        log "Creating secrets..."
        kubectl apply -f k8s/secrets/n8n-secrets.yaml
    fi
    
    # Create storage
    log "Setting up persistent storage..."
    kubectl apply -f k8s/storage/pvc.yaml
    
    # Wait for PVC to be bound
    log "Waiting for PVC to be bound (timeout: $TIMEOUT)..."
    if ! kubectl wait --for=condition=Bound pvc/n8n-data -n $NAMESPACE --timeout=$TIMEOUT; then
        error "PVC failed to bind within timeout"
    fi
    
    log "Infrastructure deployment completed"
}

# Deploy n8n application
deploy_n8n() {
    log "Deploying n8n application..."
    
    # Check if n8n is already installed
    if kubectl get deployment n8n -n $NAMESPACE &> /dev/null; then
        log "n8n is already installed, updating..."
        kubectl apply -f k8s/deployment/
    else
        log "Installing n8n..."
        kubectl apply -f k8s/deployment/
    fi
    
    # Wait for deployment to be ready
    log "Waiting for n8n deployment to be ready..."
    kubectl rollout status deployment/n8n -n $NAMESPACE --timeout=$TIMEOUT
    
    log "n8n deployment completed"
}

# Deploy supporting components
deploy_supporting_components() {
    log "Deploying supporting components..."
    
    # Apply network policy (if exists)
    if [ -f "k8s/network/network-policy.yaml" ]; then
        log "Applying network policy..."
        kubectl apply -f k8s/network/network-policy.yaml
    fi
    
    # Apply backup CronJob (if exists)
    if [ -f "k8s/backup/backup-cronjob.yaml" ]; then
        log "Setting up backup CronJob..."
        kubectl apply -f k8s/backup/backup-cronjob.yaml
    fi
    
    log "Supporting components deployed"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check pod status
    local pod_status
    pod_status=$(kubectl get pods -n $NAMESPACE -l app=n8n -o jsonpath='{.items[0].status.phase}')
    
    if [ "$pod_status" != "Running" ]; then
        error "n8n pod is not running. Status: $pod_status"
    fi
    
    # Check PVC status
    local pvc_status
    pvc_status=$(kubectl get pvc n8n-data -n $NAMESPACE -o jsonpath='{.status.phase}')
    
    if [ "$pvc_status" != "Bound" ]; then
        error "PVC is not bound. Status: $pvc_status"
    fi
    
    # Get ingress information
    local ingress_ip
    ingress_ip=$(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not available yet")
    
    log "Deployment verification completed"
    
    # Display deployment information
    echo
    log "=== Deployment Summary ==="
    echo "Namespace: $NAMESPACE"
    echo "Pod Status: $pod_status"
    echo "PVC Status: $pvc_status" 
    echo "Ingress IP: $ingress_ip"
    echo
    
    # Get the configured hostname from deployment
    local hostname
    hostname=$(grep -A1 "N8N_HOST" k8s/deployment/n8n-deployment.yaml | grep "value:" | awk '{print $3}' | tr -d '"' || echo "Not configured")
    
    if [ "$hostname" != "Not configured" ] && [ "$hostname" != "n8n.yourdomain.com" ]; then
        echo "You can access n8n at: https://$hostname"
    else
        warn "Please update the hostname in k8s/deployment/n8n-deployment.yaml"
    fi
    
    echo
    log "Next steps:"
    echo "1. Update the domain name in k8s/deployment/n8n-deployment.yaml if not done"
    echo "2. Configure your DNS to point to the ingress IP: $ingress_ip"
    echo "3. Verify the encryption key in k8s/secrets/n8n-secrets.yaml"
    echo "4. Configure Azure Storage account for backups"
    echo "5. Test SQL Server connectivity from the n8n pod"
}

# Main execution
main() {
    log "Starting n8n deployment to AKS..."
    
    preflight_checks
    deploy_infrastructure
    deploy_n8n
    deploy_supporting_components
    verify_deployment
    
    log "n8n deployment completed successfully!"
}

# Run main function
main "$@"
