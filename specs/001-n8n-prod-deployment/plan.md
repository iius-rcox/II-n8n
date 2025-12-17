# Implementation Plan: n8n Production Deployment Setup

**Branch**: `001-n8n-prod-deployment` | **Date**: 2025-12-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-n8n-prod-deployment/spec.md`

## Summary

Deploy n8n workflow automation platform to Azure Kubernetes Service (AKS) with GitOps-driven deployment via ArgoCD, automatic container image updates constrained to semver minor versions (1.x.x), daily backups to Azure Blob Storage with 30-day retention, and production-grade security configurations including network policies, TLS termination, and non-root container execution.

## Technical Context

**Language/Version**: YAML (Kubernetes manifests), Bash (backup scripts)
**Primary Dependencies**: ArgoCD, ArgoCD Image Updater, Kustomize, Azure CLI
**Storage**: Azure Blob Storage (backups), Azure Managed Disk (PVC for n8n data)
**Testing**: kubectl validation, ArgoCD sync verification, manual backup trigger tests
**Target Platform**: Azure Kubernetes Service (AKS) with ArgoCD GitOps
**Project Type**: Infrastructure-as-Code (Kubernetes manifests)
**Performance Goals**: Deploy within 15 minutes, update detection within 1 hour, 99.5% availability
**Constraints**: Semver 1.x.x image constraint, 30-day backup retention, daily 2 AM backup schedule
**Scale/Scope**: Single n8n instance with HPA (1-5 pods), single AKS cluster deployment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The constitution file contains template placeholders rather than defined principles. For this infrastructure project, the following implicit gates apply:

| Gate | Status | Notes |
|------|--------|-------|
| GitOps Principle | PASS | All infrastructure changes tracked in git via ArgoCD |
| Secrets Management | PASS | Encryption keys stored as K8s Secrets, not in git |
| Security Context | PASS | Non-root containers, dropped capabilities, network policies |
| Observability | PASS | Prometheus metrics enabled, logging configured |
| Backup/Recovery | PASS | Daily backups with 30-day retention, documented recovery |

No violations requiring justification.

## Project Structure

### Documentation (this feature)

```text
specs/001-n8n-prod-deployment/
├── plan.md              # This file
├── research.md          # Phase 0 output - best practices and patterns
├── data-model.md        # Phase 1 output - Kubernetes resource definitions
├── quickstart.md        # Phase 1 output - deployment guide
├── contracts/           # Phase 1 output - manifest schemas
│   └── k8s-resources.md # Kubernetes resource inventory
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
gitops/
└── argo-application.yaml     # ArgoCD Application with Image Updater config

k8s/
├── namespace.yaml            # n8n-prod namespace
├── kustomization.yaml        # Kustomize configuration
├── deployment/
│   ├── n8n-deployment.yaml   # Main n8n Deployment
│   ├── n8n-service.yaml      # ClusterIP Service
│   ├── n8n-ingress.yaml      # Ingress with TLS
│   ├── hpa.yaml              # Horizontal Pod Autoscaler
│   └── pdb.yaml              # Pod Disruption Budget
├── storage/
│   └── pvc.yaml              # Persistent Volume Claim
├── secrets/
│   └── n8n-secrets.yaml      # Secret template (values excluded)
├── network/
│   └── network-policy.yaml   # Network Policy rules
├── backup/
│   └── backup-cronjob.yaml   # Daily backup CronJob
└── rbac/
    ├── service-account.yaml       # n8n ServiceAccount
    └── backup-service-account.yaml # Backup job ServiceAccount
```

**Structure Decision**: Infrastructure-as-Code pattern with Kustomize-managed Kubernetes manifests. GitOps deployment via ArgoCD with automatic image updates.

## Complexity Tracking

No complexity violations. The solution uses standard Kubernetes patterns with minimal custom components.

## Implementation Phases

### Phase 0: Research
- ArgoCD Image Updater semver configuration patterns
- Azure Blob Storage lifecycle policies for 30-day retention
- Kubernetes CronJob timezone handling best practices
- Network Policy patterns for ingress-only access

### Phase 1: Design
- Data model: Kubernetes resource definitions and relationships
- Contracts: Manifest validation schemas
- Quickstart: Step-by-step deployment guide

### Phase 2: Tasks (via /speckit.tasks)
- Task breakdown for implementation
