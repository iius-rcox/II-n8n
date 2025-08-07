# SQL Server Connectivity for n8n

## Overview
This document outlines the configuration required for n8n to connect to SQL Server instances that are only accessible via VPN.

## Network Configuration

### AKS Subnet Requirements
- Ensure AKS subnet has proper route tables to SQL Server subnets
- Configure NSG rules to allow traffic from AKS to SQL Server ports (1433/1434)
- Verify SQL Server firewall allows AKS subnet ranges

### Route Table Configuration
```bash
# Example route table configuration
az network route-table create \
  --name aks-to-sql-route \
  --resource-group your-rg \
  --location eastus

az network route-table route create \
  --resource-group your-rg \
  --route-table-name aks-to-sql-route \
  --name sql-server-route \
  --address-prefix 10.0.1.0/24 \
  --next-hop-type VirtualNetworkGateway
```

### NSG Rules
```bash
# Allow outbound traffic to SQL Server
az network nsg rule create \
  --resource-group your-rg \
  --nsg-name aks-nsg \
  --name allow-sql-outbound \
  --protocol tcp \
  --priority 100 \
  --destination-port-range 1433 \
  --access allow \
  --direction outbound
```

## n8n Configuration

### Environment Variables
Add these to your `helm/n8n-values.yaml`:

```yaml
env:
  # SQL Server connection
  DB_TYPE: "mssql"
  DB_MSSQL_HOST: "your-sql-server.internal.ip"
  DB_MSSQL_PORT: "1433"
  DB_MSSQL_DATABASE: "n8n"
  DB_MSSQL_USER: "n8n_user"
  DB_MSSQL_PASSWORD: "your-password"
  
  # Additional SQL Server settings
  DB_MSSQL_OPTIONS_ENCRYPT: "true"
  DB_MSSQL_OPTIONS_TRUST_SERVER_CERTIFICATE: "true"
  DB_MSSQL_OPTIONS_ENABLE_ARITH_ABORT: "true"
```

### Connection String Format
For more complex configurations, use connection strings:

```yaml
env:
  DB_TYPE: "mssql"
  DB_MSSQL_CONNECTION_URL: "mssql://username:password@host:port/database?encrypt=true&trustServerCertificate=true"
```

## Testing Connectivity

### From n8n Pod
```bash
# Test connectivity from within the n8n pod
kubectl exec -it deployment/n8n -n n8n-prod -- nc -zv your-sql-server.internal.ip 1433
```

### Using Azure CLI
```bash
# Test from AKS node
kubectl debug node/aks-agentpool-12345678-vmss000000 -it --image=mcr.microsoft.com/aks/fundamental/base-ubuntu:v0.0.11
nc -zv your-sql-server.internal.ip 1433
```

## Troubleshooting

### Common Issues
1. **Connection Timeout**: Check NSG rules and route tables
2. **Authentication Failed**: Verify SQL Server login credentials
3. **SSL/TLS Issues**: Ensure proper certificate configuration

### Debug Commands
```bash
# Check pod network connectivity
kubectl exec -it deployment/n8n -n n8n-prod -- ping your-sql-server.internal.ip

# Check DNS resolution
kubectl exec -it deployment/n8n -n n8n-prod -- nslookup your-sql-server.internal.ip

# View n8n logs
kubectl logs deployment/n8n -n n8n-prod -f
```

## Security Considerations
- Use managed identities where possible
- Store connection strings in Kubernetes secrets
- Enable encryption for SQL Server connections
- Regularly rotate database credentials
