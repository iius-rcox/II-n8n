# AKS Node Pool Scaling Procedures

This document outlines the proper procedures for scaling AKS node pools, including cleanup of temporary surge nodes created during scale operations.

## Overview

When scaling down AKS node pools, Karpenter may create temporary "surge" nodes to hold pods during the migration. These surge nodes consume vCPU quota and must be explicitly cleaned up.

## Prerequisites

- Azure CLI with AKS credentials configured
- kubectl access to the cluster
- Sufficient permissions to manage node pools and nodeclaims

## Scaling Down a Node Pool

### Step 1: Check Current State

```bash
# Check current node pool size
az aks nodepool show \
  --resource-group rg_prod \
  --cluster-name dev-aks \
  --name systempool \
  --query "{name:name, count:count, vmSize:vmSize, provisioningState:provisioningState}" \
  -o table

# Check all nodes and their types
kubectl get nodes -o custom-columns='NAME:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,TAINTS:.spec.taints[*].key'

# Check current vCPU quota usage
az vm list-usage --location southcentralus -o table | grep -i "Total Regional vCPUs"
```

### Step 2: Initiate Scale Down

```bash
# Scale the node pool (use --no-wait for async operation)
az aks nodepool scale \
  --resource-group rg_prod \
  --cluster-name dev-aks \
  --name systempool \
  --node-count <TARGET_COUNT>

# Monitor the operation status
az aks nodepool show \
  --resource-group rg_prod \
  --cluster-name dev-aks \
  --name systempool \
  --query "provisioningState" -o tsv
```

### Step 3: Wait for Provisioning to Complete

```bash
# Poll until provisioningState is "Succeeded"
while [ "$(az aks nodepool show --resource-group rg_prod --cluster-name dev-aks --name systempool --query provisioningState -o tsv)" != "Succeeded" ]; do
  echo "Waiting for scale operation..."
  sleep 30
done
echo "Scale operation completed"
```

### Step 4: Check for Surge Nodes

**CRITICAL**: This step is often missed and leads to quota waste.

```bash
# List all Karpenter nodeclaims - look for "surge" nodes
kubectl get nodeclaims -A

# Example output showing a surge node that needs cleanup:
# NAME                 TYPE               CAPACITY    ZONE               NODE                     READY   AGE
# default-87sm9        Standard_D4as_v5   on-demand   southcentralus-1   aks-default-87sm9        True    46d
# system-surge-pj84m   Standard_D4as_v5   on-demand   southcentralus-3   aks-system-surge-pj84m   True    88m  <-- SURGE NODE

# Check what pods are running on the surge node
kubectl get pods -A --field-selector spec.nodeName=<SURGE_NODE_NAME>
```

### Step 5: Verify Node Taints

```bash
# Check if systempool nodes still have migration taints
kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key' | grep systempool

# Expected: Only "CriticalAddonsOnly" taint (normal for system pools)
# Problem: If you see "migrate" taint, pods can't schedule back
```

### Step 6: Drain the Surge Node

```bash
# Cordon the surge node (prevent new pods)
kubectl cordon <SURGE_NODE_NAME>

# Drain the surge node (move pods to other nodes)
# --ignore-daemonsets: DaemonSets will restart on other nodes automatically
# --delete-emptydir-data: Allow draining pods with emptyDir volumes
kubectl drain <SURGE_NODE_NAME> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=60

# Monitor pod migration
watch kubectl get pods -A --field-selector spec.nodeName=<SURGE_NODE_NAME>
```

### Step 7: Delete the Surge Nodeclaim

```bash
# Once drained, delete the Karpenter nodeclaim
kubectl delete nodeclaim <SURGE_NODECLAIM_NAME>

# Verify the node is removed
kubectl get nodes
```

### Step 8: Verify Quota Released

```bash
# Confirm vCPU quota is freed
az vm list-usage --location southcentralus -o table | grep -i "Total Regional vCPUs"

# The "CurrentValue" should decrease by the vCPUs of the deleted surge node
```

### Step 9: Verify Cluster Health

```bash
# Check all pods are running
kubectl get pods -A | grep -v Running | grep -v Completed

# Check node status
kubectl get nodes

# Check ArgoCD applications (if applicable)
kubectl get applications -n argocd
```

## Troubleshooting

### Surge Node Won't Drain

If pods can't be evicted:

```bash
# Check for PodDisruptionBudgets blocking eviction
kubectl get pdb -A

# Check for pods with restrictive PDBs
kubectl describe pdb <PDB_NAME> -n <NAMESPACE>

# Force delete stuck pods (use with caution)
kubectl delete pod <POD_NAME> -n <NAMESPACE> --force --grace-period=0
```

### Pods Can't Schedule on Systempool

If pods won't move to systempool nodes:

```bash
# Check systempool node taints
kubectl describe node <SYSTEMPOOL_NODE> | grep -A5 Taints

# Check pod tolerations
kubectl describe pod <POD_NAME> -n <NAMESPACE> | grep -A10 Tolerations

# Note: AKS policies prevent manual taint removal on managed node pools
# If "migrate" taints persist, you may need to restart the scale operation
```

### Quota Still Exhausted After Cleanup

```bash
# List all VMs consuming quota
az vm list --query "[?location=='southcentralus'].{name:name, size:hardwareProfile.vmSize}" -o table

# Check for any orphaned disks or resources
az disk list --query "[?location=='southcentralus' && diskState=='Unattached'].{name:name, size:diskSizeGb}" -o table
```

## Complete Scale-Down Checklist

- [ ] Record initial node count and quota usage
- [ ] Initiate scale-down operation
- [ ] Wait for `provisioningState: Succeeded`
- [ ] Check for surge nodes: `kubectl get nodeclaims -A`
- [ ] Verify systempool taints are clean (no "migrate" taint)
- [ ] Drain surge node: `kubectl drain <node>`
- [ ] Delete surge nodeclaim: `kubectl delete nodeclaim <name>`
- [ ] Verify node removed: `kubectl get nodes`
- [ ] Verify quota released: `az vm list-usage`
- [ ] Verify cluster health: all pods running
- [ ] Verify applications healthy (ArgoCD, etc.)

## Related Documentation

- [AKS Node Pool Management](https://learn.microsoft.com/en-us/azure/aks/use-multiple-node-pools)
- [Karpenter on AKS](https://learn.microsoft.com/en-us/azure/aks/karpenter)
- [Azure vCPU Quotas](https://learn.microsoft.com/en-us/azure/quotas/view-quotas)
