# N8N Deployment Checklist

## Pre-Deployment Configuration

### 1. Domain Configuration
- [ ] Update domain name in `helm/n8n-values.yaml`
  - Replace `n8n.yourdomain.com` with your actual domain
  - Update `N8N_HOST` and `WEBHOOK_URL` environment variables

### 2. Security Configuration
- [ ] Generate a strong encryption key for `N8N_ENCRYPTION_KEY`
- [ ] Update `k8s/secrets/n8n-secrets.yaml` with your encryption key
- [ ] Review and update any additional secrets (database passwords, API keys, etc.)

### 3. Azure Storage Configuration
- [ ] Create Azure Storage Account for backups
- [ ] Create container named `n8n-backups`
- [ ] Update `k8s/backup/backup-cronjob.yaml` with your storage account name
- [ ] Configure managed identity for backup access (recommended)

### 4. Network Configuration
- [ ] Verify AKS subnet has route tables to SQL Server subnets
- [ ] Configure NSG rules to allow traffic to SQL Server ports (1433/1434)
- [ ] Ensure SQL Server firewall allows AKS subnet ranges
- [ ] Test network connectivity to SQL Server

### 5. Ingress Controller
- [ ] Verify NGINX ingress controller is installed
- [ ] Confirm cert-manager is configured with `letsencrypt-prod` cluster issuer
- [ ] Test SSL certificate generation

### 6. Resource Requirements
- [ ] Verify AKS cluster has sufficient resources
- [ ] Check available storage for Premium SSD disks
- [ ] Confirm node pool can accommodate resource requests

## Deployment Steps

### 1. Initial Setup
```bash
# Verify kubectl access
kubectl cluster-info

# Verify Helm is installed
helm version

# Add n8n Helm repository
helm repo add n8n https://n8nio.github.io/n8n-helm-chart
helm repo update
```

### 2. Deploy Infrastructure
```bash
# Create namespace and RBAC
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/rbac/service-account.yaml

# Create storage
kubectl apply -f k8s/storage/storage-class.yaml
kubectl apply -f k8s/storage/pvc.yaml

# Create secrets
kubectl apply -f k8s/secrets/n8n-secrets.yaml
```

### 3. Deploy n8n
```bash
# Run deployment script
./scripts/deploy-n8n.sh
```

### 4. Post-Deployment Verification
- [ ] Check pod status: `kubectl get pods -n n8n-prod`
- [ ] Verify PVC is bound: `kubectl get pvc -n n8n-prod`
- [ ] Check ingress: `kubectl get ingress -n n8n-prod`
- [ ] Test application access: `curl -I https://your-domain.com`
- [ ] Verify SSL certificate: `kubectl get certificate -n n8n-prod`

## SQL Server Integration

### 1. Database Setup
- [ ] Create n8n database on SQL Server
- [ ] Create database user with appropriate permissions
- [ ] Test database connectivity from AKS

### 2. Environment Variables
- [ ] Add SQL Server connection details to `helm/n8n-values.yaml`
- [ ] Configure database type and connection parameters
- [ ] Test database connection from n8n pod

### 3. Network Connectivity
- [ ] Verify route tables are configured
- [ ] Test connectivity: `kubectl exec -it deployment/n8n -n n8n-prod -- nc -zv sql-server-ip 1433`
- [ ] Check DNS resolution if using hostnames

## Backup Configuration

### 1. Azure Storage Setup
- [ ] Create storage account with appropriate redundancy
- [ ] Configure container access policies
- [ ] Set up managed identity (recommended)
- [ ] Test backup job manually

### 2. Backup Testing
```bash
# Test backup manually
kubectl create job --from=cronjob/n8n-backup n8n-backup-test -n n8n-prod

# Check backup logs
kubectl logs job/n8n-backup-test -n n8n-prod

# Verify backup in Azure Storage
az storage blob list --container-name n8n-backups --account-name your-storage-account
```

## Monitoring and Maintenance

### 1. Health Monitoring
- [ ] Set up monitoring for pod health
- [ ] Configure alerts for resource usage
- [ ] Monitor backup job success/failure
- [ ] Set up log aggregation

### 2. Update Strategy
- [ ] Schedule regular maintenance windows
- [ ] Test updates in staging environment
- [ ] Configure rollback procedures
- [ ] Document update procedures

### 3. Security Review
- [ ] Regular security updates
- [ ] Rotate encryption keys
- [ ] Review network policies
- [ ] Audit access logs

## Troubleshooting Preparation

### 1. Common Issues
- [ ] Document PVC binding issues
- [ ] Prepare ingress troubleshooting steps
- [ ] Document SQL Server connectivity issues
- [ ] Prepare backup/restore procedures

### 2. Support Resources
- [ ] n8n documentation bookmarked
- [ ] Kubernetes troubleshooting guides
- [ ] Azure AKS documentation
- [ ] SQL Server connectivity guides

## Final Verification

### 1. End-to-End Testing
- [ ] Test n8n web interface access
- [ ] Verify workflow creation and execution
- [ ] Test SQL Server node functionality
- [ ] Verify backup and restore procedures
- [ ] Test update procedures

### 2. Documentation
- [ ] Update README with specific configuration details
- [ ] Document any custom configurations
- [ ] Create runbooks for common operations
- [ ] Document emergency procedures

### 3. Handover
- [ ] Provide access credentials to team members
- [ ] Schedule knowledge transfer sessions
- [ ] Document operational procedures
- [ ] Set up monitoring and alerting
