# N8N Monitoring Setup

## Overview
This document outlines the monitoring setup for n8n in your AKS cluster, including metrics collection, alerting, and log aggregation.

## 1. Prometheus Monitoring

### ServiceMonitor for n8n
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: n8n
  namespace: n8n-prod
  labels:
    app: n8n
    release: prometheus
spec:
  selector:
    matchLabels:
      app: n8n
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    scrapeTimeout: 10s
```

### Custom Metrics Configuration
Add these environment variables to your n8n deployment:
```yaml
env:
- name: N8N_METRICS
  value: "true"
- name: N8N_METRICS_PREFIX
  value: "n8n_"
```

## 2. Alerting Rules

### PrometheusRule for n8n
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: n8n-alerts
  namespace: n8n-prod
  labels:
    app: n8n
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
  - name: n8n.rules
    rules:
    - alert: N8NPodDown
      expr: up{app="n8n"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "n8n pod is down"
        description: "n8n pod has been down for more than 1 minute"
    
    - alert: N8NHighCPU
      expr: rate(container_cpu_usage_seconds_total{container="n8n"}[5m]) > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "n8n high CPU usage"
        description: "n8n is using more than 80% CPU for 5 minutes"
    
    - alert: N8NHighMemory
      expr: (container_memory_usage_bytes{container="n8n"} / container_spec_memory_limit_bytes{container="n8n"}) > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "n8n high memory usage"
        description: "n8n is using more than 85% of memory limit"
    
    - alert: N8NWorkflowFailures
      expr: increase(n8n_workflow_executions_failed_total[1h]) > 10
      labels:
        severity: warning
      annotations:
        summary: "n8n workflow failures"
        description: "More than 10 workflow failures in the last hour"
```

## 3. Log Aggregation

### Fluent Bit Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: n8n-prod
data:
  fluent-bit.conf: |
    [SERVICE]
        Parsers_File    parsers.conf
        HTTP_Server     On
        HTTP_Listen     0.0.0.0
        HTTP_Port       2020

    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/n8n-*.log
        Parser            docker
        DB                /var/log/flb_kube.db
        Skip_Long_Lines   On
        Refresh_Interval  10

    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL           https://kubernetes.default.svc:443
        Merge_Log          On
        K8S-Logging.Parser On
        K8S-Logging.Exclude On

    [OUTPUT]
        Name        azure
        Match       kube.*
        Customer_ID your-workspace-id
        Log_Type    n8n-logs
```

## 4. Custom Dashboards

### Grafana Dashboard
Create a Grafana dashboard with the following panels:

1. **Pod Health**
   - Pod status
   - Restart count
   - Uptime

2. **Resource Usage**
   - CPU usage
   - Memory usage
   - Storage usage

3. **Workflow Metrics**
   - Workflow executions per hour
   - Success/failure rates
   - Average execution time

4. **Network Metrics**
   - Request rate
   - Response times
   - Error rates

## 5. Health Checks

### Enhanced Health Check Endpoint
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 5678
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /healthz
    port: 5678
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

startupProbe:
  httpGet:
    path: /healthz
    port: 5678
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 30
```

## 6. Performance Monitoring

### Resource Monitoring
- Set up alerts for resource thresholds
- Monitor disk I/O for database operations
- Track network bandwidth usage

### Workflow Performance
- Monitor workflow execution times
- Track queue depths
- Alert on workflow failures

## 7. Security Monitoring

### Audit Logging
```yaml
env:
- name: N8N_LOG_LEVEL
  value: "info"
- name: N8N_AUDIT_LOG_ENABLED
  value: "true"
- name: N8N_AUDIT_LOG_LEVEL
  value: "info"
```

### Security Alerts
- Failed authentication attempts
- Unusual access patterns
- Configuration changes

## 8. Backup Monitoring

### Backup Success Alerts
```yaml
- alert: N8NBackupFailed
  expr: increase(n8n_backup_jobs_failed_total[24h]) > 0
  for: 1h
  labels:
    severity: critical
  annotations:
    summary: "n8n backup failed"
    description: "n8n backup job has failed in the last 24 hours"
```

## 9. Integration with Azure Monitor

### Azure Monitor Agent
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ama-config
  namespace: n8n-prod
data:
  config: |
    {
      "workspaceId": "your-workspace-id",
      "workspaceKey": "your-workspace-key"
    }
```

## 10. Monitoring Commands

### Check Metrics
```bash
# Port forward to Prometheus
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring

# Check n8n metrics
curl http://localhost:9090/api/v1/query?query=up{app="n8n"}
```

### Check Logs
```bash
# View n8n logs
kubectl logs -n n8n-prod deployment/n8n -f

# Check audit logs
kubectl logs -n n8n-prod deployment/n8n | grep "AUDIT"
```

### Check Alerts
```bash
# View active alerts
kubectl get prometheusrules -n n8n-prod

# Check alert manager
kubectl port-forward svc/alertmanager-operated 9093:9093 -n monitoring
```

## 11. Troubleshooting

### Common Issues
1. **Metrics not available**: Check if n8n metrics endpoint is enabled
2. **Alerts not firing**: Verify PrometheusRule is applied
3. **Logs not appearing**: Check Fluent Bit configuration

### Debug Commands
```bash
# Check ServiceMonitor
kubectl describe servicemonitor n8n -n n8n-prod

# Check PrometheusRule
kubectl describe prometheusrule n8n-alerts -n n8n-prod

# Test metrics endpoint
kubectl exec -n n8n-prod deployment/n8n -- curl -s http://localhost:5678/metrics
```

## 12. Best Practices

1. **Set appropriate thresholds** for alerts
2. **Use meaningful alert descriptions**
3. **Implement alert silencing** for maintenance windows
4. **Regular review** of monitoring rules
5. **Document alert procedures**
6. **Test monitoring setup** regularly
