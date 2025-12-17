# Tasks: n8n Production Deployment Setup

**Input**: Design documents from `/specs/001-n8n-prod-deployment/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No test tasks included (not explicitly requested in spec). Verification tasks use kubectl validation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

## Path Conventions

This is an Infrastructure-as-Code project:
- **Kubernetes manifests**: `k8s/` directory
- **GitOps config**: `gitops/` directory
- **Documentation**: `specs/001-n8n-prod-deployment/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prerequisites verification and configuration updates

- [ ] T001 Verify AKS cluster access with `kubectl cluster-info` *(requires cluster access)*
- [ ] T002 Verify ArgoCD installation with `kubectl get pods -n argocd` *(requires cluster access)*
- [ ] T003 [P] Verify ArgoCD Image Updater installation with `kubectl get deployment argocd-image-updater -n argocd` *(requires cluster access)*
- [ ] T004 [P] Verify ingress controller installation with `kubectl get pods -n ingress-nginx` *(requires cluster access)*
- [x] T005 Update repository URL in `gitops/argo-application.yaml` - Updated to `https://github.com/iius-rcox/II-n8n.git`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T006 Create n8n-prod namespace with `kubectl apply -f k8s/namespace.yaml` *(requires cluster access)*
- [ ] T007 Generate n8n encryption key and create secret in n8n-prod namespace *(requires cluster access)*
- [ ] T008 Create git-creds secret in argocd namespace for Image Updater write-back *(requires cluster access)*
- [ ] T009 [P] Create Azure Storage Account for backups (if not exists) *(requires Azure access)*
- [ ] T010 [P] Create n8n-backups container in Azure Storage Account *(requires Azure access)*
- [ ] T011 Configure Azure managed identity with Storage Blob Data Contributor role *(requires Azure access)*
- [ ] T012 Update Azure Storage Account name in `k8s/backup/backup-cronjob.yaml` *(requires Azure storage account name)*
- [x] T013 Created Azure Blob lifecycle policy file `k8s/backup/lifecycle-policy.json` for 30-day retention
- [ ] T014 Verify DNS configuration for n8n.ii-us.com pointing to ingress controller *(requires DNS access)*

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Deploy n8n to Production (Priority: P1) MVP

**Goal**: Deploy n8n workflow automation platform to AKS via ArgoCD GitOps

**Independent Test**: Navigate to https://n8n.ii-us.com and verify n8n login/setup page loads

### Implementation for User Story 1

- [x] T015 [US1] Verified kustomization includes all resources in `k8s/kustomization.yaml` - includes namespace, storage, rbac, secrets, network, deployment, service, ingress, pdb, hpa, backup
- [x] T016 [US1] Verified Deployment configuration in `k8s/deployment/n8n-deployment.yaml` - image n8nio/n8n:1.72, resources (500m-2000m CPU, 1-4Gi memory), liveness/readiness probes
- [x] T017 [P] [US1] Verified Service configuration in `k8s/deployment/n8n-service.yaml` - ClusterIP, port 5678
- [x] T018 [P] [US1] Verified Ingress configuration in `k8s/deployment/n8n-ingress.yaml` - host n8n.ii-us.com, TLS, Azure Web App Routing
- [x] T019 [P] [US1] Verified PVC configuration in `k8s/storage/pvc.yaml` - 20Gi, managed-premium storageClass
- [x] T020 [P] [US1] Verified ServiceAccount in `k8s/rbac/service-account.yaml` - n8n SA with Role/RoleBinding
- [ ] T021 [US1] Apply ArgoCD Application with `kubectl apply -f gitops/argo-application.yaml` *(requires cluster access)*
- [ ] T022 [US1] Monitor ArgoCD sync status until healthy with `argocd app get n8n-prod` *(requires cluster access)*
- [ ] T023 [US1] Verify pod is running with `kubectl get pods -n n8n-prod` *(requires cluster access)*
- [ ] T024 [US1] Verify n8n accessible via configured domain (https://n8n.ii-us.com) *(requires deployment)*

**Checkpoint**: User Story 1 complete - n8n is deployed and accessible via HTTPS

---

## Phase 4: User Story 2 - Automatic Container Image Updates (Priority: P2)

**Goal**: Enable automatic n8n version updates via ArgoCD Image Updater with semver 1.x.x constraint

**Independent Test**: Check Image Updater logs show n8n image monitoring and verify update annotations

### Implementation for User Story 2

- [x] T025 [US2] Verified Image Updater annotations in `gitops/argo-application.yaml` match research.md patterns
- [x] T026 [US2] Verified semver constraint allows 1.x.x tags (regexp: `^1\.[0-9]+\.[0-9]+$`)
- [x] T027 [US2] Verified and updated ignore-tags to include `latest,edge,nightly,dev,alpha,beta`
- [x] T028 [US2] Verified write-back-method is `git` and write-back-target is `kustomization`
- [x] T029 [US2] Verified git-branch annotation points to `main`
- [ ] T030 [US2] Test Image Updater detection with `kubectl logs deployment/argocd-image-updater -n argocd` *(requires cluster access)*
- [x] T031 [US2] Verified kustomization.yaml has images section with `n8nio/n8n` and `newTag: "1.72"`

**Checkpoint**: User Story 2 complete - Image Updater monitors and can update n8n versions

---

## Phase 5: User Story 3 - Automated Backups to Azure Storage (Priority: P2)

**Goal**: Configure daily backups at 2 AM with 30-day retention

**Independent Test**: Manually trigger backup job and verify backup file in Azure Storage

### Implementation for User Story 3

- [x] T032 [US3] Verified CronJob schedule is `0 2 * * *` in `k8s/backup/backup-cronjob.yaml`
- [x] T033 [US3] Verified CronJob timeZone is `America/New_York`
- [x] T034 [US3] Verified backup script includes 30-day retention cleanup logic (RETENTION_DAYS=30)
- [x] T035 [US3] Verified backup ServiceAccount in `k8s/rbac/backup-service-account.yaml` - n8n-backup SA with Azure workload identity annotations
- [ ] T036 [US3] Apply backup CronJob via ArgoCD sync *(requires cluster access)*
- [ ] T037 [US3] Manually trigger test backup with `kubectl create job --from=cronjob/n8n-backup test-backup -n n8n-prod` *(requires cluster access)*
- [ ] T038 [US3] Verify backup file exists in Azure Storage container *(requires Azure access)*
- [ ] T039 [US3] Clean up test backup job with `kubectl delete job test-backup -n n8n-prod` *(requires cluster access)*

**Checkpoint**: User Story 3 complete - Automated backups configured with 30-day retention

---

## Phase 6: User Story 4 - Secure Production Configuration (Priority: P3)

**Goal**: Apply security hardening with network policies, TLS, and non-root containers

**Independent Test**: Verify security context on running pods and test network policy blocks unauthorized access

### Implementation for User Story 4

- [x] T040 [US4] Verified Deployment securityContext in `k8s/deployment/n8n-deployment.yaml` - runAsNonRoot: true, runAsUser: 1000, capabilities drop ALL
- [x] T041 [US4] Verified NetworkPolicy in `k8s/network/network-policy.yaml` - ingress from app-routing-system/ingress-nginx, egress for DNS/HTTPS
- [x] T042 [P] [US4] Verified Ingress TLS configuration with cert-manager letsencrypt-prod issuer, ssl-redirect annotations
- [x] T043 [P] [US4] Verified Secret template in `k8s/secrets/n8n-secrets.yaml` - placeholder value with instructions to use external secrets
- [ ] T044 [US4] Verify pod security context with `kubectl get pod -n n8n-prod -o jsonpath='{.items[0].spec.securityContext}'` *(requires cluster access)*
- [ ] T045 [US4] Verify network policy applied with `kubectl get networkpolicy -n n8n-prod` *(requires cluster access)*
- [ ] T046 [US4] Test TLS certificate validity by accessing https://n8n.ii-us.com *(requires deployment)*

**Checkpoint**: User Story 4 complete - Security hardening applied and verified

---

## Phase 7: User Story 5 - High Availability and Scaling (Priority: P3)

**Goal**: Enable horizontal pod autoscaling and pod disruption budget

**Independent Test**: Verify HPA is monitoring metrics and PDB is configured

### Implementation for User Story 5

- [x] T047 [US5] Verified HPA configuration in `k8s/deployment/hpa.yaml` - minReplicas: 1, maxReplicas: 1 (SQLite limitation noted), CPU 70%, Memory 80%
- [x] T048 [US5] Verified PDB configuration in `k8s/deployment/pdb.yaml` - minAvailable: 1
- [x] T049 [US5] Verified Deployment replicas=1 in `k8s/deployment/n8n-deployment.yaml`, managed by HPA
- [ ] T050 [US5] Verify HPA status with `kubectl get hpa -n n8n-prod` *(requires cluster access)*
- [ ] T051 [US5] Verify PDB status with `kubectl get pdb -n n8n-prod` *(requires cluster access)*
- [ ] T052 [US5] Verify metrics endpoint enabled with `kubectl exec -it deployment/n8n -n n8n-prod -- curl localhost:5678/metrics` *(requires cluster access)*

**Checkpoint**: User Story 5 complete - Autoscaling and availability configured

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T053 Run full quickstart.md validation (specs/001-n8n-prod-deployment/quickstart.md) *(requires deployment)*
- [ ] T054 Verify all ArgoCD sync is healthy with `argocd app get n8n-prod` *(requires cluster access)*
- [x] T055 [P] Verified .gitignore excludes secrets - k8s/secrets/n8n-secrets.yaml, *.key, *.env, kubeconfig*
- [x] T056 [P] SETUP.md already contains complete deployment instructions
- [x] T057 Documented implementation status in tasks.md - all manifests verified, cluster access tasks pending
- [ ] T058 Final deployment verification - access n8n and create test workflow *(requires deployment)*

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (P1) should complete first as it's the base deployment
  - US2, US3 can proceed after US1 (both P2, parallel if staffed)
  - US4, US5 can proceed after US1 (both P3, parallel if staffed)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Requires US1 complete (needs running ArgoCD Application)
- **User Story 3 (P2)**: Requires US1 complete (needs running namespace and PVC)
- **User Story 4 (P3)**: Can run parallel with US2/US3 after US1
- **User Story 5 (P3)**: Can run parallel with US2/US3/US4 after US1

### Within Each User Story

- Verify tasks before apply tasks
- Core configuration before validation
- kubectl checks after resource application

### Parallel Opportunities

- T003, T004 can run in parallel (different controllers)
- T009, T010 can run in parallel (Azure resources)
- T017, T018, T019, T020 can run in parallel (different manifest files)
- T042, T043 can run in parallel (different security aspects)
- T055, T056 can run in parallel (different concerns)

---

## Parallel Example: User Story 1

```bash
# Launch all manifest verifications together:
Task: "Verify Service configuration in k8s/deployment/n8n-service.yaml"
Task: "Verify Ingress configuration in k8s/deployment/n8n-ingress.yaml"
Task: "Verify PVC configuration in k8s/storage/pvc.yaml"
Task: "Verify ServiceAccount in k8s/rbac/service-account.yaml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (verify prerequisites)
2. Complete Phase 2: Foundational (create secrets, configure Azure)
3. Complete Phase 3: User Story 1 (deploy n8n via ArgoCD)
4. **STOP and VALIDATE**: Access https://n8n.ii-us.com
5. Deploy/demo if ready - n8n is functional

### Incremental Delivery

1. Complete Setup + Foundational -> Foundation ready
2. Add User Story 1 -> Test independently -> n8n accessible (MVP!)
3. Add User Story 2 -> Automatic updates enabled
4. Add User Story 3 -> Backups operational
5. Add User Story 4 -> Security hardened
6. Add User Story 5 -> HA and scaling ready
7. Each story adds production-readiness without breaking previous

### Infrastructure Focus

This project is primarily verification and configuration:
- Most Kubernetes manifests already exist
- Tasks focus on updating placeholder values
- Key work: secrets creation, Azure configuration, validation

---

## Summary

| Phase | Story | Tasks | Completed | Pending (Cluster/Azure) |
|-------|-------|-------|-----------|------------------------|
| Setup | - | 5 | 1 | 4 |
| Foundational | - | 9 | 1 | 8 |
| US1 (P1) | Deploy n8n | 10 | 6 | 4 |
| US2 (P2) | Auto Updates | 7 | 6 | 1 |
| US3 (P2) | Backups | 8 | 4 | 4 |
| US4 (P3) | Security | 7 | 4 | 3 |
| US5 (P3) | HA/Scaling | 6 | 3 | 3 |
| Polish | - | 6 | 3 | 3 |
| **Total** | | **58** | **28** | **30** |

**Status**: All manifest verification tasks complete. Remaining tasks require:
- AKS cluster access (kubectl)
- Azure subscription access (storage account, managed identity)
- DNS configuration
- Final deployment validation

---

## Notes

- [P] tasks = different files/resources, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Most manifests exist - tasks focus on configuration and verification
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
