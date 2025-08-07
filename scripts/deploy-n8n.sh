#!/bin/bash
# deploy-n8n.sh

set -e

echo "Starting n8n deployment to AKS..."

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    exit 1
fi

# Add n8n Helm repository
echo "Adding n8n Helm repository..."
helm repo add n8n https://n8nio.github.io/n8n-helm-chart
helm repo update

# Create namespace and RBAC
echo "Creating namespace and RBAC..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/rbac/service-account.yaml

# Create storage
echo "Setting up storage..."
kubectl apply -f k8s/storage/storage-class.yaml
kubectl apply -f k8s/storage/pvc.yaml

# Create secrets
echo "Creating secrets..."
kubectl apply -f k8s/secrets/n8n-secrets.yaml

# Wait for PVC to be bound
echo "Waiting for PVC to be bound..."
kubectl wait --for=condition=Bound pvc/n8n-data -n n8n-prod --timeout=300s

# Install n8n via Helm
echo "Installing n8n via Helm..."
helm install n8n n8n/n8n \
  --namespace n8n-prod \
  --values helm/n8n-values.yaml \
  --wait

# Apply network policy
echo "Applying network policy..."
kubectl apply -f k8s/network/network-policy.yaml

# Apply backup CronJob
echo "Setting up backup CronJob..."
kubectl apply -f k8s/backup/backup-cronjob.yaml

# Wait for deployment to be ready
echo "Waiting for n8n deployment to be ready..."
kubectl rollout status deployment/n8n -n n8n-prod

echo "n8n deployment completed successfully!"
echo "You can access n8n at: https://n8n.yourdomain.com"
echo ""
echo "Next steps:"
echo "1. Update the domain name in helm/n8n-values.yaml"
echo "2. Configure your DNS to point to the ingress IP"
echo "3. Update the encryption key in k8s/secrets/n8n-secrets.yaml"
echo "4. Configure Azure Storage account for backups"
