# Feature Specification: n8n Production Deployment Setup

**Feature Branch**: `001-n8n-prod-deployment`
**Created**: 2025-12-16
**Status**: Draft
**Input**: User description: "n8n Production Deployment Setup - Configure AKS deployment with ArgoCD GitOps, automatic image updates, Azure storage backups, and security configurations"

## Clarifications

### Session 2025-12-16

- Q: What is the backup retention period? → A: 30 days (standard retention for production)
- Q: How often should backups run? → A: Daily at 2 AM (standard production schedule)
- Q: What version constraint strategy for automatic updates? → A: Semver minor (1.x.x) - auto-update patches and minor versions only

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy n8n to Production (Priority: P1)

As a DevOps engineer, I need to deploy n8n workflow automation platform to an Azure Kubernetes Service (AKS) cluster so that our organization can run automated workflows in a production environment.

**Why this priority**: This is the foundational capability - without a working deployment, no other features can function. Organizations cannot use n8n until it's deployed and accessible.

**Independent Test**: Can be fully tested by deploying the base n8n application and verifying it's accessible via the configured domain, delivering a functional workflow automation platform.

**Acceptance Scenarios**:

1. **Given** an AKS cluster with ArgoCD installed, **When** the administrator applies the ArgoCD Application manifest, **Then** n8n deploys successfully and becomes accessible via HTTPS within 10 minutes
2. **Given** n8n is deployed, **When** a user navigates to the configured domain, **Then** they see the n8n login/setup page
3. **Given** the deployment completes, **When** checking pod status, **Then** all n8n pods report "Running" status with no restart loops

---

### User Story 2 - Automatic Container Image Updates (Priority: P2)

As a DevOps engineer, I need n8n to automatically update to new versions when they're released so that our production environment stays current with security patches and new features without manual intervention.

**Why this priority**: Keeping n8n updated is critical for security and functionality, but the system must be deployed first (P1) before automatic updates can occur.

**Independent Test**: Can be tested by triggering a version check cycle and verifying that new images are detected and the deployment manifest is updated via git commit.

**Acceptance Scenarios**:

1. **Given** ArgoCD Image Updater is configured with semver minor constraint (1.x.x), **When** a new n8n patch or minor version is published, **Then** the image updater detects and applies the update within its check interval
2. **Given** a new image version is detected, **When** the image updater processes the update, **Then** it commits the updated image tag back to the git repository
3. **Given** a new commit is pushed by image updater, **When** ArgoCD detects the change, **Then** the deployment automatically updates to the new version
4. **Given** automatic updates are enabled, **When** an update occurs, **Then** the deployment follows the update strategy with zero or minimal downtime
5. **Given** a new major version (e.g., 2.0.0) is published, **When** the image updater checks for updates, **Then** the major version is ignored and requires manual upgrade

---

### User Story 3 - Automated Backups to Azure Storage (Priority: P2)

As a system administrator, I need n8n data to be automatically backed up to Azure Storage so that we can recover from data loss or system failures.

**Why this priority**: Data protection is critical for production systems, but the deployment must exist first. This is equal priority to automatic updates as both support production reliability.

**Independent Test**: Can be tested by manually triggering the backup job and verifying the backup file appears in Azure Storage with valid content.

**Acceptance Scenarios**:

1. **Given** backup is configured with Azure Storage credentials, **When** 2 AM occurs daily, **Then** a backup job executes and uploads data to the configured storage container
2. **Given** a backup job runs, **When** it completes successfully, **Then** a backup file is created in the Azure Storage container with a timestamp-based name
3. **Given** multiple backups exist, **When** checking the storage container, **Then** backup files from the past 30 days are retained and older backups are automatically purged
4. **Given** a backup job fails, **When** checking job status, **Then** the failure is logged with diagnostic information

---

### User Story 4 - Secure Production Configuration (Priority: P3)

As a security administrator, I need the n8n deployment to follow security best practices so that our production environment is protected against common vulnerabilities.

**Why this priority**: Security hardening is important but the system must be deployed and operational first. This ensures the running system meets security standards.

**Independent Test**: Can be tested by running security scans and verifying network policies, TLS, and security contexts are properly configured.

**Acceptance Scenarios**:

1. **Given** network policies are applied, **When** attempting to access n8n from unauthorized sources, **Then** the connection is blocked
2. **Given** TLS is configured on ingress, **When** accessing n8n via HTTPS, **Then** the connection uses valid certificates with no security warnings
3. **Given** security context is configured, **When** inspecting the running container, **Then** it runs as non-root with dropped capabilities
4. **Given** the encryption key secret exists, **When** n8n encrypts sensitive workflow data, **Then** the data is protected using the provided key

---

### User Story 5 - High Availability and Scaling (Priority: P3)

As a platform engineer, I need n8n to scale based on demand and maintain availability during disruptions so that workflows continue running during peak usage or maintenance.

**Why this priority**: Scaling and availability are production optimizations that build on the base deployment. Important for mature production use but not required for initial functionality.

**Independent Test**: Can be tested by simulating load and verifying HPA scales pods, or by deleting a pod and verifying PDB maintains minimum availability.

**Acceptance Scenarios**:

1. **Given** HPA is configured, **When** CPU/memory usage exceeds the threshold, **Then** additional pods are created automatically
2. **Given** multiple pods are running, **When** a pod is terminated, **Then** PDB ensures minimum available pods are maintained
3. **Given** load decreases, **When** utilization drops below the threshold, **Then** excess pods are scaled down after the stabilization period

---

### Edge Cases

- What happens when the git repository is temporarily unavailable during an image update commit?
- How does the system handle Azure Storage authentication failures during backup?
- What happens if the encryption key secret is deleted or corrupted?
- How does the deployment behave if the PVC storage runs out of space?
- What happens when ArgoCD sync fails due to invalid manifests?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy n8n to AKS using ArgoCD GitOps workflow
- **FR-002**: System MUST expose n8n via HTTPS through Kubernetes Ingress with valid TLS certificates
- **FR-003**: System MUST automatically detect and deploy new n8n container image versions within the same major version (semver 1.x.x constraint) using ArgoCD Image Updater
- **FR-004**: System MUST commit image version updates back to the git repository to maintain GitOps state
- **FR-005**: System MUST perform daily backups of n8n data to Azure Blob Storage at 2 AM
- **FR-006**: System MUST store n8n encryption keys as Kubernetes Secrets (not in git)
- **FR-007**: System MUST enforce network policies to restrict traffic to authorized sources only
- **FR-008**: System MUST run containers with non-root security context and dropped capabilities
- **FR-009**: System MUST support horizontal pod autoscaling based on resource utilization
- **FR-010**: System MUST maintain minimum pod availability during disruptions via Pod Disruption Budget
- **FR-011**: System MUST provide Prometheus metrics endpoint for monitoring integration
- **FR-012**: System MUST persist n8n workflow data and configurations on durable storage (PVC)
- **FR-013**: System MUST retain backups for 30 days and automatically purge older backups

### Key Entities

- **n8n Deployment**: The main application workload running n8n container instances with configurable replicas, resource limits, and environment variables
- **ArgoCD Application**: GitOps configuration defining the source repository, sync policy, and image update annotations for automated deployment
- **Backup Job**: Scheduled task that captures n8n data and uploads to Azure Storage with timestamp-based naming
- **Secrets**: Sensitive configuration data including encryption keys and git credentials stored outside version control
- **Network Policy**: Rules defining allowed ingress/egress traffic patterns for the n8n namespace
- **Ingress**: External access point routing HTTPS traffic to the n8n service with TLS termination

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Administrators can deploy n8n from scratch to a running, accessible state within 15 minutes
- **SC-002**: New n8n versions are automatically detected and deployed within 1 hour of release (configurable check interval)
- **SC-003**: Backups complete successfully at least 95% of scheduled runs over any 30-day period
- **SC-004**: System maintains 99.5% availability during normal operations (excluding planned maintenance)
- **SC-005**: Zero security vulnerabilities from running containers as root or with excessive capabilities
- **SC-006**: System scales from 1 to 5 pods within 5 minutes in response to increased load
- **SC-007**: Recovery from backup can be completed within 30 minutes by following documented procedures
- **SC-008**: All production secrets remain outside version control with zero secrets committed to git

## Assumptions

- AKS cluster is already provisioned and accessible via kubectl
- ArgoCD is pre-installed on the cluster
- Azure Storage account exists or will be created as a prerequisite
- DNS is configured to point the desired domain to the cluster's ingress controller
- Ingress controller (e.g., nginx-ingress) is installed on the cluster
- cert-manager or similar is available for TLS certificate management
- Prometheus monitoring stack is available for metrics collection (optional but assumed for full monitoring)
- Git repository hosting supports webhook or polling-based change detection for ArgoCD
