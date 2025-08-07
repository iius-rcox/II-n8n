# N8N Disaster Recovery Procedures

## Overview
This document outlines the disaster recovery procedures for n8n in your AKS cluster, including backup restoration, failover procedures, and recovery time objectives.

## 1. Recovery Time Objectives (RTO) & Recovery Point Objectives (RPO)

### RTO: 30 minutes
- Time to restore n8n to a functional state
- Includes pod restart and health checks

### RPO: 24 hours
- Maximum data loss in case of disaster
- Based on daily backup schedule

## 2. Backup Verification

### Daily Backup Verification
```bash
# Check backup job status
kubectl get jobs -n n8n-prod | grep backup

# Verify backup in Azure Storage
az storage blob list \
  --container-name n8n-backups \
  --account-name your-storage-account \
  --query "[?contains(name, '$(date +%Y%m%d)')].{name:name, size:properties.contentLength, created:properties.creationTime}" \
  --output table
```

### Backup Integrity Check
```bash
# Download and verify backup
az storage blob download \
  --container-name n8n-backups \
  --name n8n-backup-$(date +%Y%m%d)-*.tar.gz \
  --file /tmp/backup-test.tar.gz \
  --account-name your-storage-account

# Extract and verify contents
tar -tzf /tmp/backup-test.tar.gz | head -10
```

## 3. Recovery Procedures

### Scenario 1: Pod Failure
```bash
# Check pod status
kubectl get pods -n n8n-prod

# Describe pod for details
kubectl describe pod -n n8n-prod -l app=n8n

# Check logs
kubectl logs -n n8n-prod deployment/n8n

# Restart deployment if needed
kubectl rollout restart deployment/n8n -n n8n-prod

# Wait for rollout
kubectl rollout status deployment/n8n -n n8n-prod
```

### Scenario 2: PVC Corruption
```bash
# Stop n8n deployment
kubectl scale deployment n8n --replicas=0 -n n8n-prod

# Delete corrupted PVC
kubectl delete pvc n8n-data -n n8n-prod

# Restore from backup
kubectl create job --from=cronjob/n8n-backup n8n-restore-$(date +%Y%m%d-%H%M%S) -n n8n-prod

# Recreate PVC
kubectl apply -f k8s/storage/pvc.yaml

# Restart deployment
kubectl scale deployment n8n --replicas=1 -n n8n-prod
```

### Scenario 3: Complete Cluster Failure

#### Step 1: Verify AKS Cluster Status
```bash
# Check cluster status
az aks show --name your-cluster-name --resource-group your-rg --query "powerState"

# If cluster is down, restart it
az aks start --name your-cluster-name --resource-group your-rg
```

#### Step 2: Redeploy Infrastructure
```bash
# Apply all infrastructure components
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/rbac/
kubectl apply -f k8s/storage/pvc.yaml
kubectl apply -f k8s/secrets/n8n-secrets.yaml
```

#### Step 3: Restore Data
```bash
# Create restore job
kubectl create job n8n-restore-$(date +%Y%m%d-%H%M%S) \
  --from=cronjob/n8n-backup \
  -n n8n-prod

# Monitor restore progress
kubectl logs -f job/n8n-restore-$(date +%Y%m%d-%H%M%S) -n n8n-prod
```

#### Step 4: Deploy Application
```bash
# Deploy n8n
kubectl apply -f k8s/deployment/

# Verify deployment
kubectl rollout status deployment/n8n -n n8n-prod
```

## 4. Data Recovery Procedures

### Manual Backup Restoration
```bash
# Create temporary pod for restoration
kubectl run n8n-restore --image=mcr.microsoft.com/azure-cli:latest \
  --rm -it --restart=Never \
  --overrides='{
    "spec": {
      "volumes": [{"name": "n8n-data", "persistentVolumeClaim": {"claimName": "n8n-data"}}],
      "containers": [{
        "name": "restore",
        "image": "mcr.microsoft.com/azure-cli:latest",
        "volumeMounts": [{"name": "n8n-data", "mountPath": "/n8n-data"}],
        "command": ["/bin/bash"],
        "args": ["-c", "az login --identity && az storage blob download --container-name n8n-backups --name n8n-backup-20240807-120000.tar.gz --file /tmp/backup.tar.gz --account-name your-storage-account && cd /n8n-data && tar -xzf /tmp/backup.tar.gz --strip-components=1"]
      }]
    }
  }' -n n8n-prod
```

### Point-in-Time Recovery
```bash
# List available backups
az storage blob list \
  --container-name n8n-backups \
  --account-name your-storage-account \
  --query "[].{name:name, created:properties.creationTime}" \
  --output table

# Restore specific backup
BACKUP_NAME="n8n-backup-20240807-120000.tar.gz"
kubectl create job n8n-restore-specific \
  --from=cronjob/n8n-backup \
  --overrides='{
    "spec": {
      "template": {
        "spec": {
          "containers": [{
            "name": "backup",
            "env": [{"name": "RESTORE_BACKUP", "value": "'$BACKUP_NAME'"}]
          }]
        }
      }
    }
  }' -n n8n-prod
```

## 5. Network Recovery

### Ingress Recovery
```bash
# Check ingress status
kubectl get ingress -n n8n-prod

# Recreate ingress if needed
kubectl apply -f k8s/deployment/n8n-ingress.yaml

# Verify DNS resolution
nslookup n8n.yourdomain.com
```

### SSL Certificate Recovery
```bash
# Check certificate status
kubectl get certificate -n n8n-prod

# Recreate certificate if needed
kubectl delete certificate n8n-tls -n n8n-prod
kubectl apply -f k8s/deployment/n8n-ingress.yaml
```

## 6. Configuration Recovery

### Secrets Recovery
```bash
# Check secrets
kubectl get secrets -n n8n-prod

# Recreate secrets if needed
kubectl apply -f k8s/secrets/n8n-secrets.yaml
```

### RBAC Recovery
```bash
# Recreate RBAC
kubectl apply -f k8s/rbac/
```

## 7. Testing Recovery Procedures

### Monthly Recovery Test
```bash
# Create test namespace
kubectl create namespace n8n-test

# Deploy test instance
kubectl apply -f k8s/ -n n8n-test

# Test backup/restore
kubectl create job --from=cronjob/n8n-backup n8n-test-backup -n n8n-test

# Verify functionality
kubectl port-forward -n n8n-test svc/n8n 5679:5678 &
curl http://localhost:5679/healthz

# Cleanup
kubectl delete namespace n8n-test
```

## 8. Communication Plan

### Incident Response Team
- **Primary**: DevOps Engineer
- **Secondary**: System Administrator
- **Escalation**: IT Manager

### Communication Channels
- **Internal**: Slack/Teams channel
- **External**: Email notifications
- **Status Page**: Update during recovery

## 9. Documentation Requirements

### Post-Recovery Documentation
1. **Incident Report**
   - Root cause analysis
   - Timeline of events
   - Actions taken

2. **Lessons Learned**
   - What worked well
   - Areas for improvement
   - Process updates

3. **Recovery Metrics**
   - Actual RTO vs target
   - Data loss assessment
   - User impact

## 10. Preventive Measures

### Regular Health Checks
```bash
# Daily health check script
#!/bin/bash
NAMESPACE="n8n-prod"

# Check pod status
POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=n8n -o jsonpath='{.items[0].status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo "ALERT: n8n pod is not running. Status: $POD_STATUS"
    exit 1
fi

# Check health endpoint
if ! kubectl exec -n $NAMESPACE deployment/n8n -- wget -q --spider http://localhost:5678/healthz; then
    echo "ALERT: n8n health check failed"
    exit 1
fi

echo "n8n is healthy"
```

### Backup Monitoring
```bash
# Check backup success
BACKUP_SUCCESS=$(kubectl get jobs -n n8n-prod | grep backup | grep Completed | wc -l)
if [ $BACKUP_SUCCESS -eq 0 ]; then
    echo "ALERT: No successful backups in the last 24 hours"
    exit 1
fi
```

## 11. Recovery Validation

### Functional Testing
1. **User Authentication**
2. **Workflow Execution**
3. **Database Connectivity**
4. **External Integrations**

### Performance Testing
1. **Response Times**
2. **Resource Usage**
3. **Concurrent Users**

## 12. Escalation Procedures

### Level 1: Automated Recovery
- Pod restart
- PVC recreation
- Service restoration

### Level 2: Manual Intervention
- Backup restoration
- Configuration recovery
- Network troubleshooting

### Level 3: Vendor Support
- Azure support for AKS issues
- n8n community support
- Third-party integration support

---

**Last Updated**: August 7, 2025
**Next Review**: September 7, 2025
