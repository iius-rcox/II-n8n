#!/bin/bash
# update-n8n.sh

# Set maintenance window
echo "Starting n8n maintenance update..."

# Get current version
CURRENT_VERSION=$(helm get values n8n -n n8n-prod -o json | jq -r '.image.tag')
echo "Current version: $CURRENT_VERSION"

# Check for latest version
LATEST_VERSION=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | jq -r '.tag_name')
echo "Latest version: $LATEST_VERSION"

# Update Helm chart
helm repo update n8n

# Backup current configuration
helm get values n8n -n n8n-prod > n8n-values-backup-$(date +%Y%m%d).yaml

# Upgrade with latest image
helm upgrade n8n n8n/n8n \
  --namespace n8n-prod \
  --values helm/n8n-values.yaml \
  --set image.tag=$LATEST_VERSION \
  --wait

# Verify deployment
kubectl rollout status deployment/n8n -n n8n-prod

echo "Update completed successfully!"
