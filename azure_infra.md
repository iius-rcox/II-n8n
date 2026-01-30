# Azure Infrastructure Documentation

**Last Updated:** 2025-01-13
**Cluster Context:** dev-aks

---

## Azure Kubernetes Service (AKS) Cluster

### Cluster Information

| Property | Value |
|----------|-------|
| **Cluster Name** | dev-aks |
| **Control Plane URL** | https://dns-275668076-mklxmuv2.hcp.southcentralus.azmk8s.io:443 |
| **Region** | South Central US |
| **Kubernetes Version** | v1.32.6 - v1.33.3 (mixed) |
| **Tenant ID** | 953922e6-5370-4a01-a3d5-773a30df726b |
| **Subscription** | Test Subscription (3c2442b9-104d-43b2-832a-ae52f893e1b4) |

### Cluster Services

| Service | Endpoint |
|---------|----------|
| CoreDNS | https://dns-275668076-mklxmuv2.hcp.southcentralus.azmk8s.io:443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy |
| Metrics Server | https://dns-275668076-mklxmuv2.hcp.southcentralus.azmk8s.io:443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy |

---

## Node Pools

### Active Nodes (6 total)

| Node Name | Role | Status | K8s Version | Internal IP | OS | Runtime |
|-----------|------|--------|-------------|-------------|----|---------|
| aks-default-87sm9 | Worker | Ready | v1.33.3 | 10.0.0.21 | Azure Linux 3.0 | containerd://2.0.0 |
| aks-optimized-15094557-vmss000000 | Worker | Ready | v1.33.3 | 10.0.0.20 | Ubuntu 22.04.5 LTS | containerd://1.7.28-1 |
| aks-optimized-15094557-vmss000001 | Worker | Ready | v1.33.3 | 10.0.0.110 | Ubuntu 22.04.5 LTS | containerd://1.7.28-1 |
| aks-system-surge-sx9ch | System | Ready | v1.33.3 | 10.0.0.107 | Azure Linux 3.0 | containerd://2.0.0 |
| aks-systempool-18197317-vmss000000 | System | Ready | v1.32.6 | 10.0.0.15 | Azure Linux 3.0 | containerd://2.0.0 |
| aks-systempool-18197317-vmss000001 | System | Ready | v1.32.6 | 10.0.0.11 | Azure Linux 3.0 | containerd://2.0.0 |

### Node Resource Usage

| Node | CPU (cores) | CPU % | Memory | Memory % |
|------|-------------|-------|--------|----------|
| aks-default-87sm9 | 311m | 8% | 8586Mi | 72% |
| aks-optimized-15094557-vmss000000 | 275m | 14% | 5293Mi | 91% |
| aks-optimized-15094557-vmss000001 | 198m | 10% | 2992Mi | 51% |
| aks-system-surge-sx9ch | 122m | 3% | 2991Mi | 25% |
| aks-systempool-18197317-vmss000000 | 129m | 3% | 3966Mi | 68% |
| aks-systempool-18197317-vmss000001 | 106m | 2% | 4300Mi | 74% |

---

## Azure Key Vault

### Key Vault Configuration

| Property | Value |
|----------|-------|
| **Name** | iius-akv |
| **URL** | https://iius-akv.vault.azure.net |
| **Auth Method** | Workload Identity |
| **Tenant ID** | 953922e6-5370-4a01-a3d5-773a30df726b |

### Secret Management Integration

- **External Secrets Operator:** v0.14.4
- **ClusterSecretStore:** azure-keyvault (configured in `k8s/secrets/external-secrets/secret-store.yaml`)
- **Service Account:** external-secrets-sa (namespace: external-secrets)
- **SecretProviderClass:** azure-keyvault-secrets (namespace: expenseflow-staging)

---

## Namespaces

| Namespace | Status | Age | Purpose |
|-----------|--------|-----|---------|
| aks-command | Active | 78d | AKS system commands |
| app-routing-system | Active | 168d | Azure Web App Routing (nginx ingress) |
| argocd | Active | 27d | GitOps continuous delivery |
| cert-manager | Active | 87d | TLS certificate management |
| credit-card-processor | Active | 99d | Credit card processing application |
| default | Active | 168d | Default namespace |
| expenseflow-dev | Active | 40d | ExpenseFlow development environment |
| expenseflow-staging | Active | 40d | ExpenseFlow staging environment |
| external-secrets | Active | 27d | External Secrets Operator |
| gatekeeper-system | Active | 168d | OPA Gatekeeper policy enforcement |
| keel | Active | 98d | Kubernetes deployment automation |
| kube-node-lease | Active | 168d | Node heartbeat leases |
| kube-public | Active | 168d | Public cluster information |
| kube-system | Active | 168d | Core Kubernetes components |
| monitoring | Active | 157d | Monitoring stack |
| n8n-prod | Active | 159d | n8n workflow automation (production) |

---

## All Running Pods

### app-routing-system (2 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| nginx-6cfbdbdf-hg9fd | 1/1 | Running | aks-default-87sm9 |
| nginx-6cfbdbdf-w7n5t | 1/1 | Running | aks-default-87sm9 |

### argocd (7 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| argocd-application-controller-0 | 1/1 | Running | aks-default-87sm9 |
| argocd-applicationset-controller-954fcfbf8-t7njq | 1/1 | Running | aks-default-87sm9 |
| argocd-image-updater-78446c7c5c-52b24 | 1/1 | Running | aks-default-87sm9 |
| argocd-redis-59f85f7c69-v66vc | 1/1 | Running | aks-default-87sm9 |
| argocd-repo-server-55dcf45958-s6dhj | 1/1 | Running | aks-default-87sm9 |
| argocd-server-fb76b9cdb-9zz8f | 1/1 | Running | aks-default-87sm9 |

### cert-manager (3 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| cert-manager-cainjector-5b6dd96846-dq7mk | 1/1 | Running | aks-default-87sm9 |
| cert-manager-d4f76848-4hm78 | 1/1 | Running | aks-default-87sm9 |
| cert-manager-webhook-565879cd59-fjlv9 | 1/1 | Running | aks-default-87sm9 |

### credit-card-processor (4 pods)

| Pod | Ready | Status | Node | Notes |
|-----|-------|--------|------|-------|
| backend-5c5bfdf67-8r258 | 1/1 | Running | aks-default-87sm9 | |
| celery-worker-8574d55fd9-pnvmk | 0/1 | Running | aks-default-87sm9 | 18541 restarts - needs attention |
| frontend-5f948cfd5-f96fv | 1/1 | Running | aks-default-87sm9 | |
| postgres-0 | 1/1 | Running | aks-default-87sm9 | StatefulSet |

### expenseflow-dev (11 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| cm-acme-http-solver-cm67v | 1/1 | Running | aks-optimized-vmss000001 |
| expenseflow-api-5987dffd95-2gccj | 1/1 | Running | aks-optimized-vmss000000 |
| expenseflow-api-5987dffd95-7rzrd | 1/1 | Running | aks-default-87sm9 |
| supabase-backup-29436600-m4qgk | 0/1 | Completed | aks-optimized-vmss000001 |
| supabase-backup-29469720-bbhln | 0/1 | Completed | aks-optimized-vmss000001 |
| supabase-backup-29471160-xhfgm | 0/1 | Completed | aks-optimized-vmss000001 |
| supabase-supabase-db-646f954b5-mblgb | 1/1 | Running | aks-default-87sm9 |
| supabase-supabase-kong-557f9df449-qpqwl | 1/1 | Running | aks-default-87sm9 |
| supabase-supabase-meta-5497cc79b-2kxfs | 1/1 | Running | aks-optimized-vmss000000 |
| supabase-supabase-realtime-675b5955cf-bwnbc | 1/1 | Running | aks-optimized-vmss000000 |
| supabase-supabase-rest-5b44db754d-kdfjv | 1/1 | Running | aks-optimized-vmss000000 |
| supabase-supabase-studio-6f48cc9b8f-hcsp5 | 1/1 | Running | aks-optimized-vmss000001 |

### expenseflow-staging (3 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| expenseflow-api-5758ff99cd-9j265 | 1/1 | Running | aks-optimized-vmss000001 |
| expenseflow-frontend-5cb76cdb66-gcvz5 | 1/1 | Running | aks-default-87sm9 |
| expenseflow-frontend-5cb76cdb66-jc69c | 1/1 | Running | aks-optimized-vmss000000 |

### external-secrets (3 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| external-secrets-78f5c76b57-z2mqg | 1/1 | Running | aks-system-surge-sx9ch |
| external-secrets-cert-controller-5d95b8f676-9r8p9 | 1/1 | Running | aks-default-87sm9 |
| external-secrets-webhook-55c884b4b8-jbctx | 1/1 | Running | aks-default-87sm9 |

### gatekeeper-system (3 pods)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| gatekeeper-audit-55768b56d7-jflpm | 1/1 | Running | aks-optimized-vmss000000 |
| gatekeeper-controller-f465c8d88-2jdjf | 1/1 | Running | aks-optimized-vmss000000 |
| gatekeeper-controller-f465c8d88-9ndv7 | 1/1 | Running | aks-optimized-vmss000000 |

### keel (1 pod)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| keel-57d7cd9c44-pcbck | 1/1 | Running | aks-default-87sm9 |

### n8n-prod (1 pod)

| Pod | Ready | Status | Node |
|-----|-------|--------|------|
| n8n-65b9c59fdc-2w6r4 | 1/1 | Running | aks-default-87sm9 |

### kube-system (67 pods)

Core system components including:
- **Networking:** Cilium CNI (6 pods), Azure CNS (6 pods), IP Masq Agent (6 pods)
- **DNS:** CoreDNS (2 pods), CoreDNS Autoscaler (1 pod)
- **Storage:** CSI Azure Disk (6 pods), CSI Azure File (6 pods), Secrets Store CSI Driver (6 pods)
- **Monitoring:** AMA Logs (6 pods), AMA Metrics (5 pods)
- **Scaling:** KEDA (6 pods), VPA (4 pods), Metrics Server (2 pods)
- **Security:** Azure Policy (2 pods), Workload Identity Webhook (2 pods)
- **Connectivity:** Konnectivity Agent (3 pods), Cloud Node Manager (6 pods)

---

## Deployments Summary

### Application Deployments

| Namespace | Deployment | Replicas | Image |
|-----------|------------|----------|-------|
| argocd | argocd-server | 1/1 | quay.io/argoproj/argocd:v2.13.2 |
| argocd | argocd-repo-server | 1/1 | quay.io/argoproj/argocd:v2.13.2 |
| argocd | argocd-image-updater | 1/1 | quay.io/argoprojlabs/argocd-image-updater:v0.14.0 |
| cert-manager | cert-manager | 1/1 | quay.io/jetstack/cert-manager-controller:v1.19.1 |
| credit-card-processor | backend | 1/1 | iiusacr.azurecr.io/expense-backend:v1.0.15 |
| credit-card-processor | frontend | 1/1 | iiusacr.azurecr.io/expense-frontend:v1.0.15 |
| credit-card-processor | celery-worker | 0/1 | iiusacr.azurecr.io/expense-backend:v1.0.13 |
| expenseflow-dev | expenseflow-api | 2/2 | iiusacr.azurecr.io/expenseflow-api:v1.0.0 |
| expenseflow-dev | supabase-supabase-db | 1/1 | supabase/postgres:15.8.1.085 |
| expenseflow-dev | supabase-supabase-studio | 1/1 | supabase/studio:2025.11.26-sha-8f096b5 |
| expenseflow-staging | expenseflow-api | 1/1 | iiusacr.azurecr.io/expenseflow-api:v1.10.0-41d2882 |
| expenseflow-staging | expenseflow-frontend | 2/2 | iiusacr.azurecr.io/expenseflow-frontend:v1.4.48-8e9a426 |
| external-secrets | external-secrets | 1/1 | external-secrets:v0.14.4 |
| keel | keel | 1/1 | keelhq/keel:0.19.1 |
| n8n-prod | n8n | 1/1 | n8nio/n8n:1.123.6 |

### StatefulSets

| Namespace | StatefulSet | Replicas |
|-----------|-------------|----------|
| argocd | argocd-application-controller | 1/1 |
| credit-card-processor | postgres | 1/1 |

---

## Services & Ingress

### External Load Balancer

| Service | External IP | Ports |
|---------|-------------|-------|
| app-routing-system/nginx | 4.151.29.139 | 80, 443 |

### Ingress Resources

| Namespace | Ingress | Host | Class |
|-----------|---------|------|-------|
| argocd | argocd-server | k8.ii-us.com | webapprouting.kubernetes.azure.com |
| credit-card-processor | credit-card-ingress | credit-card.ii-us.com | webapprouting.kubernetes.azure.com |
| expenseflow-dev | expenseflow-api | dev.expense.ii-us.com | nginx |
| expenseflow-dev | supabase-studio | studio.expense.ii-us.com | webapprouting.kubernetes.azure.com |
| expenseflow-staging | expenseflow-api | staging.expense.ii-us.com | webapprouting.kubernetes.azure.com |
| n8n-prod | n8n | n8n.ii-us.com | webapprouting.kubernetes.azure.com |

---

## Persistent Storage

### Persistent Volume Claims

| Namespace | PVC Name | Status | Capacity | Storage Class |
|-----------|----------|--------|----------|---------------|
| credit-card-processor | credit-card-temp-pvc | Bound | 50Gi | (default) |
| credit-card-processor | postgres-storage-postgres-0 | Bound | 10Gi | managed-csi-premium |
| expenseflow-dev | supabase-backup-pvc | Bound | 10Gi | managed-csi-premium |
| expenseflow-dev | supabase-supabase-db-pvc | Bound | 20Gi | managed-csi-premium |
| n8n-prod | n8n-data | Bound | 20Gi | managed-premium |

**Total Persistent Storage:** ~110 Gi

---

## Container Registry

| Property | Value |
|----------|-------|
| **Registry** | iiusacr.azurecr.io |
| **Type** | Azure Container Registry |

### Custom Images

- `iiusacr.azurecr.io/expense-backend:v1.0.15`
- `iiusacr.azurecr.io/expense-frontend:v1.0.15`
- `iiusacr.azurecr.io/expenseflow-api:v1.0.0`
- `iiusacr.azurecr.io/expenseflow-api:v1.10.0-41d2882`
- `iiusacr.azurecr.io/expenseflow-frontend:v1.4.48-8e9a426`

---

## Infrastructure Components

### GitOps & CI/CD
- **ArgoCD:** v2.13.2 - GitOps continuous delivery
- **ArgoCD Image Updater:** v0.14.0 - Automatic image updates
- **Keel:** v0.19.1 - Kubernetes deployment automation

### Security & Secrets
- **External Secrets Operator:** v0.14.4 - Azure Key Vault integration
- **Secrets Store CSI Driver:** Azure Key Vault CSI provider
- **cert-manager:** v1.19.1 - TLS certificate management
- **OPA Gatekeeper:** v3.20.1-2 - Policy enforcement
- **Azure Policy:** v1.14.2 - Azure policy integration
- **Workload Identity:** v1.5.1 - Pod identity management

### Networking
- **Cilium:** v1.17.7 - CNI networking
- **Azure Web App Routing:** nginx ingress controller v1.13.1
- **CoreDNS:** v1.12.1-7 - DNS resolution

### Monitoring & Scaling
- **Azure Monitor (AMA):** Container insights & Prometheus metrics
- **KEDA:** v2.17.1 - Event-driven autoscaling
- **VPA:** v1.2.1 - Vertical Pod Autoscaler
- **Metrics Server:** v0.7.2 - Resource metrics

---

## Known Issues

1. **celery-worker** (credit-card-processor): 18,541 restarts - CrashLoopBackOff behavior, needs investigation
2. **aks-optimized-vmss000000**: Memory at 91% - consider scaling or pod redistribution

---

## Quick Reference

### Access URLs

| Application | URL |
|-------------|-----|
| ArgoCD UI | https://k8.ii-us.com |
| n8n | https://n8n.ii-us.com |
| ExpenseFlow Dev | https://dev.expense.ii-us.com |
| ExpenseFlow Staging | https://staging.expense.ii-us.com |
| Supabase Studio | https://studio.expense.ii-us.com |
| Credit Card Processor | https://credit-card.ii-us.com |

### Key Commands

```bash
# Get cluster info
kubectl cluster-info

# View all pods
kubectl get pods --all-namespaces

# Check node resources
kubectl top nodes

# View pod logs
kubectl logs -n <namespace> <pod-name>

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
