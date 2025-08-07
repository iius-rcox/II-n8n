# N8N AKS Deployment

This repository contains the complete Kubernetes configuration for deploying n8n on Azure Kubernetes Service (AKS) with production-grade features including persistent storage, automated backups, network policies, and GitOps integration.

## Architecture Overview

### Core Components
- **Namespace**: `n8n-prod`
- **Storage**: Azure Disk (Premium SSD) for persistent data
- **Network**: Integrated with vnet-prod via AKS subnet
- **Updates**: Scheduled maintenance with Helm upgrades
- **Backup**: Daily automated backups with 30-day retention

## Quick Start

### Prerequisites
- Azure Kubernetes Service (AKS) cluster
- kubectl configured to access your AKS cluster
- Helm 3.x installed
- Azure CLI configured (for backup functionality)

### 1. Clone and Configure
```bash
git clone <your-repo-url>
cd II-n8n

# Update configuration files with your values:
# - Domain name in helm/n8n-values.yaml
# - Encryption key in k8s/secrets/n8n-secrets.yaml
# - Azure Storage account in k8s/backup/backup-cronjob.yaml
```

### 2. Deploy n8n
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run the deployment script
./scripts/deploy-n8n.sh
```

### 3. Verify Deployment
```bash
# Check deployment status
kubectl get pods -n n8n-prod

# Check ingress
kubectl get ingress -n n8n-prod

# View logs
kubectl logs deployment/n8n -n n8n-prod -f
```

## Configuration Files

### Kubernetes Resources
- `k8s/namespace.yaml` - Production namespace
- `k8s/storage/` - Storage class and PVC configuration
- `k8s/rbac/` - Service account and RBAC rules
- `k8s/secrets/` - Secret management
- `k8s/network/` - Network policies
- `k8s/backup/` - Automated backup CronJob

### Helm Configuration
- `helm/n8n-values.yaml` - Complete Helm values for n8n deployment

### Scripts
- `scripts/deploy-n8n.sh` - Complete deployment script
- `scripts/update-n8n.sh` - Maintenance update script

### GitOps
- `gitops/argo-application.yaml` - ArgoCD application configuration

## Features

### 🗄️ Persistent Storage
- 20Gi Premium SSD storage
- Expandable volume configuration
- Data persistence across pod restarts

### 🔒 Security
- Network policies for traffic control
- RBAC with minimal permissions
- Non-root container execution
- Secret management for sensitive data

### 🔄 Automated Backups
- Daily backups at 2 AM
- 30-day retention policy
- Azure Blob Storage integration
- Automated cleanup of old backups

### 🌐 Ingress & TLS
- NGINX ingress controller
- Automatic SSL certificate management
- HTTPS redirection
- Custom domain support

### 📊 Monitoring & Health Checks
- Liveness and readiness probes
- Resource limits and requests
- Health endpoint monitoring

### 🔧 Maintenance
- Automated Helm updates
- Configuration backup before updates
- Rollback capabilities
- Scheduled maintenance windows

## SQL Server Connectivity

For VPN-only SQL Server access, see [SQL Server Connectivity Guide](docs/SQL_SERVER_CONNECTIVITY.md).

## Resource Requirements

### Recommended Limits
- **CPU Requests**: 500m (0.5 cores)
- **CPU Limits**: 2000m (2 cores)
- **Memory Requests**: 1Gi
- **Memory Limits**: 4Gi
- **Storage**: 20Gi Premium SSD

## Maintenance

### Update n8n
```bash
./scripts/update-n8n.sh
```

### Manual Backup
```bash
kubectl create job --from=cronjob/n8n-backup n8n-backup-manual -n n8n-prod
```

### View Backup Status
```bash
kubectl get jobs -n n8n-prod
kubectl logs job/n8n-backup-manual -n n8n-prod
```

## Troubleshooting

### Common Issues

1. **PVC Not Bound**
   ```bash
   kubectl describe pvc n8n-data -n n8n-prod
   ```

2. **Pod Not Starting**
   ```bash
   kubectl describe pod -l app=n8n -n n8n-prod
   kubectl logs -l app=n8n -n n8n-prod
   ```

3. **Ingress Issues**
   ```bash
   kubectl get ingress -n n8n-prod
   kubectl describe ingress n8n -n n8n-prod
   ```

### Network Connectivity
```bash
# Test SQL Server connectivity
kubectl exec -it deployment/n8n -n n8n-prod -- nc -zv your-sql-server.internal.ip 1433
```

## GitOps Deployment

If using ArgoCD:

1. Update the repository URL in `gitops/argo-application.yaml`
2. Apply the ArgoCD application:
   ```bash
   kubectl apply -f gitops/argo-application.yaml
   ```

## Security Notes

- Change the default encryption key in `k8s/secrets/n8n-secrets.yaml`
- Update domain names in `helm/n8n-values.yaml`
- Configure Azure Storage account for backups
- Review and adjust network policies as needed
- Regularly update n8n to latest versions

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review n8n documentation
3. Check Kubernetes logs and events
4. Verify Azure infrastructure configuration