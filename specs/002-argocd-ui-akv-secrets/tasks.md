# Tasks: ArgoCD Web UI Setup and Azure Key Vault Secrets Migration

**Input**: Design documents from `/specs/002-argocd-ui-akv-secrets/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No automated tests requested - validation via kubectl and manual verification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- **Infrastructure manifests**: `k8s/`, `argocd/`
- **Documentation**: `docs/`
- **External Secrets**: `k8s/secrets/external-secrets/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and Azure infrastructure provisioning

- [x] T001 Create Azure Key Vault with RBAC authorization via Azure CLI in docs/azure-setup.md
- [x] T002 [P] Create Managed Identity for External Secrets Operator via Azure CLI
- [x] T003 [P] Enable Workload Identity on AKS cluster via Azure CLI
- [x] T004 Assign Key Vault Secrets User role to Managed Identity via Azure CLI
- [x] T005 Create Federated Credential linking K8s ServiceAccount to Managed Identity
- [x] T006 Store n8n-encryption-key secret in Azure Key Vault
- [x] T007 [P] Create directory structure for new manifests: argocd/, k8s/secrets/external-secrets/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Install External Secrets Operator - MUST complete before any user story

**⚠️ CRITICAL**: No user story work can begin until ESO is installed and ClusterSecretStore is configured

- [x] T008 Install External Secrets Operator via Helm in external-secrets namespace
- [x] T009 Verify ESO controller deployment is ready via kubectl
- [x] T010 Create ServiceAccount for ESO with Workload Identity annotation in k8s/secrets/external-secrets/service-account.yaml
- [x] T011 Create ClusterSecretStore connecting to Azure Key Vault in k8s/secrets/external-secrets/secret-store.yaml
- [x] T012 Verify ClusterSecretStore status shows Ready via kubectl

**Checkpoint**: Foundation ready - External Secrets Operator can now sync secrets from AKV

---

## Phase 3: User Story 1 - Access ArgoCD Web Interface (Priority: P1) 🎯 MVP

**Goal**: Enable DevOps engineers to access ArgoCD web UI via browser to view application dashboard

**Independent Test**: Navigate to ArgoCD URL via port-forward, login with admin credentials, view n8n-prod application

### Implementation for User Story 1

- [x] T013 [US1] Patch argocd-cmd-params-cm ConfigMap to set server.insecure=true in argocd/argocd-cmd-params-cm.yaml
- [x] T014 [US1] Update argocd-cm ConfigMap with external URL in argocd/argocd-cm.yaml
- [x] T015 [US1] Restart argocd-server deployment to apply ConfigMap changes
- [x] T016 [US1] Verify ArgoCD server is running in insecure mode via kubectl logs
- [x] T017 [US1] Test ArgoCD UI access via port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:80
- [x] T018 [US1] Retrieve initial admin password from argocd-initial-admin-secret
- [x] T019 [US1] Login to ArgoCD UI and verify n8n-prod application is visible

**Checkpoint**: ArgoCD UI accessible via port-forward with local authentication working

---

## Phase 4: User Story 2 - Secure Secret Storage in Azure Key Vault (Priority: P1)

**Goal**: Migrate n8n secrets from Kubernetes secrets to Azure Key Vault with automatic sync

**Independent Test**: Verify n8n deployment retrieves N8N_ENCRYPTION_KEY from AKV-synced secret, no plain secrets in k8s/secrets/

### Implementation for User Story 2

- [x] T020 [US2] Create ExternalSecret for n8n-secrets in k8s/secrets/external-secrets/n8n-external-secret.yaml
- [x] T021 [US2] Apply ExternalSecret and verify secret syncs from AKV via kubectl get externalsecret
- [x] T022 [US2] Verify Kubernetes Secret n8n-secrets is created with correct data in n8n-prod namespace
- [x] T023 [US2] Update k8s/kustomization.yaml to include external-secrets resources
- [x] T024 [US2] Remove plain-text secret from k8s/secrets/n8n-secrets.yaml (keep as template/example)
- [x] T025 [US2] Restart n8n deployment to verify it uses AKV-synced secret
- [x] T026 [US2] Verify n8n application starts successfully with secret from AKV

**Checkpoint**: n8n secrets managed by External Secrets Operator, plain-text secrets removed from Git

---

## Phase 5: User Story 3 - Secure External Access to ArgoCD UI (Priority: P2)

**Goal**: Expose ArgoCD UI externally with TLS encryption via Azure Web App Routing ingress

**Independent Test**: Access https://argocd.ii-us.com from external network, verify valid TLS certificate

**Dependencies**: Requires US1 completion (ArgoCD server configured)

### Implementation for User Story 3

- [x] T027 [US3] Create ArgoCD ingress manifest with TLS configuration in argocd/ingress.yaml
- [x] T028 [US3] Apply ArgoCD ingress to cluster via kubectl
- [x] T029 [US3] Verify cert-manager issues TLS certificate for argocd.ii-us.com
- [x] T030 [US3] Wait for certificate to be Ready via kubectl get certificate -n argocd
- [x] T031 [US3] Configure DNS record for argocd.ii-us.com pointing to ingress IP
- [x] T032 [US3] Test external access to https://argocd.ii-us.com
- [x] T033 [US3] Verify TLS certificate is valid and trusted in browser

**Checkpoint**: ArgoCD UI accessible externally with valid TLS certificate

---

## Phase 6: User Story 4 - ArgoCD Authentication Configuration (Priority: P2)

**Goal**: Secure ArgoCD with proper authentication, store admin password in AKV

**Independent Test**: Attempt login with invalid credentials (fails), valid credentials (succeeds)

**Dependencies**: Requires US1 and US2 completion (ArgoCD running, AKV integration working)

### Implementation for User Story 4

- [x] T034 [US4] Store ArgoCD admin password in Azure Key Vault as argocd-admin-password
- [x] T035 [US4] Create ExternalSecret for ArgoCD admin secret in k8s/secrets/external-secrets/argocd-external-secret.yaml
- [x] T036 [US4] Apply ExternalSecret and verify ArgoCD secret syncs from AKV
- [x] T037 [US4] Create argocd-rbac-cm ConfigMap with RBAC policies in argocd/argocd-rbac-cm.yaml
- [x] T038 [US4] Apply RBAC configuration to ArgoCD namespace
- [x] T039 [US4] Test login with invalid credentials (should fail with error message)
- [x] T040 [US4] Test login with valid admin credentials (should succeed)
- [x] T041 [US4] Verify session expiration and re-authentication requirement

**Checkpoint**: ArgoCD authentication secured with admin password from AKV

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, GitOps integration, and final validation

- [x] T042 [P] Create Azure setup documentation in docs/azure-setup.md
- [x] T043 [P] Create argocd/kustomization.yaml to manage ArgoCD resources
- [x] T044 Update gitops/argo-application.yaml to reference new argocd/ directory (if managing ArgoCD via ArgoCD)
- [x] T045 [P] Document secret rotation procedure in docs/secret-rotation.md
- [x] T046 Run full validation per quickstart.md verification steps
- [x] T047 Verify all acceptance scenarios from spec.md
- [x] T048 Clean up temporary resources and test configurations

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001-T007) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2)
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) - can run parallel with US1
- **User Story 3 (Phase 5)**: Depends on US1 (ArgoCD server must be configured)
- **User Story 4 (Phase 6)**: Depends on US1 and US2 (needs ArgoCD + AKV integration)
- **Polish (Phase 7)**: Depends on US1, US2, US3, US4 completion

### User Story Dependencies

```
                ┌─────────────────────┐
                │  Phase 1: Setup     │
                └──────────┬──────────┘
                           │
                           ▼
                ┌─────────────────────┐
                │Phase 2: Foundational│
                │   (ESO Install)     │
                └──────────┬──────────┘
                           │
           ┌───────────────┼───────────────┐
           │                               │
           ▼                               ▼
┌─────────────────────┐         ┌─────────────────────┐
│ US1: ArgoCD UI      │         │ US2: AKV Secrets    │
│ (P1 - MVP)          │         │ (P1)                │
└──────────┬──────────┘         └──────────┬──────────┘
           │                               │
           ├───────────────┐               │
           │               │               │
           ▼               │               │
┌─────────────────────┐    │               │
│ US3: External TLS   │    │               │
│ (P2)                │    │               │
└──────────┬──────────┘    │               │
           │               ▼               │
           │    ┌─────────────────────┐    │
           │    │ US4: Auth Config    │◄───┘
           │    │ (P2)                │
           │    └──────────┬──────────┘
           │               │
           └───────┬───────┘
                   │
                   ▼
          ┌─────────────────────┐
          │  Phase 7: Polish    │
          └─────────────────────┘
```

### Parallel Opportunities

**Within Setup (Phase 1)**:
- T002 and T003 can run in parallel (different Azure resources)

**Within Foundational (Phase 2)**:
- T010 and T011 can run in parallel after T008-T009 (different K8s resources)

**Across User Stories**:
- US1 and US2 can run in parallel after Foundational phase
- US3 must wait for US1
- US4 must wait for US1 and US2

**Within Polish (Phase 7)**:
- T042, T043, T045 can run in parallel (different files)

---

## Parallel Example: User Stories 1 and 2

After Foundational phase completes, launch US1 and US2 in parallel:

```bash
# Developer A: User Story 1 (ArgoCD UI)
Task: "T013 [US1] Patch argocd-cmd-params-cm ConfigMap..."
Task: "T014 [US1] Update argocd-cm ConfigMap..."
# ...continue through T019

# Developer B: User Story 2 (AKV Secrets)
Task: "T020 [US2] Create ExternalSecret for n8n-secrets..."
Task: "T021 [US2] Apply ExternalSecret and verify..."
# ...continue through T026
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (Azure infrastructure)
2. Complete Phase 2: Foundational (ESO installation)
3. Complete Phase 3: User Story 1 (ArgoCD UI access)
4. **STOP and VALIDATE**: Test ArgoCD UI via port-forward
5. Demo: "ArgoCD UI accessible with basic auth"

### Incremental Delivery

1. **Setup + Foundational** → Azure/ESO infrastructure ready
2. **Add User Story 1** → ArgoCD UI accessible (MVP!)
3. **Add User Story 2** → Secrets in AKV (security milestone)
4. **Add User Story 3** → External TLS access (production-ready)
5. **Add User Story 4** → Full auth setup (complete feature)

### Parallel Team Strategy

With 2 developers after Foundational phase:

| Developer A | Developer B |
|-------------|-------------|
| US1: ArgoCD UI Config | US2: AKV Secret Migration |
| US3: External TLS (after US1) | US4: Auth Config (after US1+US2) |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- kubectl validation replaces automated tests for infrastructure
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Azure CLI commands should be documented in docs/azure-setup.md
