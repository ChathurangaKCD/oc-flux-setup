# OpenChoreo 0.12.0 Flux GitOps Setup

This repository contains Flux GitOps manifests for deploying OpenChoreo 0.12.0 on a k3d cluster.

## Repository Structure

```
oc-flux-setup/
├── clusters/openchoreo-dev/
│   ├── flux-system/                              # Flux components (managed by bootstrap)
│   ├── kustomization.yaml                        # Entry point
│   ├── infrastructure-kustomization.yaml         # cert-manager + helm repos
│   ├── openchoreo-control-plane-kustomization.yaml
│   ├── openchoreo-data-plane-kustomization.yaml
│   ├── openchoreo-build-plane-kustomization.yaml
│   ├── openchoreo-observability-plane-kustomization.yaml
│   └── plane-crs-kustomization.yaml
├── infrastructure/
│   ├── sources/helm-repositories.yaml            # Helm repos (jetstack, openchoreo, argo, eso, twuni)
│   └── cert-manager/
├── apps/
│   ├── openchoreo-control-plane/
│   │   ├── helmrelease.yaml
│   │   └── values.yaml
│   ├── openchoreo-data-plane/
│   │   ├── helmrelease.yaml
│   │   ├── eso-crds-helmrelease.yaml             # Pre-install External Secrets CRDs
│   │   └── values.yaml
│   ├── openchoreo-build-plane/
│   │   ├── helmrelease.yaml
│   │   ├── argo-crds-helmrelease.yaml            # Pre-install Argo Workflows CRDs
│   │   ├── registry-helmrelease.yaml             # Docker registry for builds
│   │   └── values.yaml
│   ├── openchoreo-observability-plane/
│   │   ├── helmrelease.yaml
│   │   └── values.yaml
│   └── openchoreo-plane-crs/                     # DataPlane, BuildPlane, ObservabilityPlane CRs
└── k3d-config.yaml
```

## Dependency Chain

```
flux-system
    └── infrastructure (cert-manager + helm repos)
            └── openchoreo-control-plane
                    ├── openchoreo-data-plane
                    │       └── external-secrets-crds (pre-req)
                    ├── openchoreo-build-plane
                    │       ├── argo-workflows-crds (pre-req)
                    │       └── registry (pre-req)
                    ├── openchoreo-observability-plane
                    └── openchoreo-plane-crs
```

## CRD Pre-Installation (Important)

The build-plane and data-plane charts have **post-install hooks** that reference CRDs installed by the chart itself (ClusterWorkflowTemplate, ClusterSecretStore). Helm fails because:

1. Helm installs chart templates (including CRDs as sub-chart templates)
2. Helm immediately tries to process post-install hooks
3. Hook processing requires `KubeClient.Build()` to parse manifests
4. CRDs aren't registered with the API server yet (takes a few seconds)
5. Error: "no matches for kind ClusterWorkflowTemplate"

**Solution:** Pre-install CRDs using separate HelmReleases that the main releases depend on:
- `argo-workflows-crds` - Installs only Argo CRDs (controller/server disabled)
- `external-secrets-crds` - Installs only ESO CRDs (operator disabled)

See: https://github.com/helm/helm/blob/main/pkg/action/hooks.go

## Prerequisites

- k3d v5.8+
- kubectl v1.32+
- Flux CLI v2.0+
- GitHub personal access token

### Create k3d Cluster

```bash
# Use the included config
k3d cluster create --config=k3d-config.yaml

# Or download from OpenChoreo
curl -s https://raw.githubusercontent.com/openchoreo/openchoreo/release-v0.12/install/k3d/single-cluster/config.yaml | k3d cluster create --config=-
```

## Installation

### Bootstrap with Flux

```bash
export GITHUB_TOKEN=<your-pat>

flux bootstrap github \
  --owner=<your-github-user> \
  --repository=oc-flux-setup \
  --path=clusters/openchoreo-dev \
  --personal \
  --token-auth
```

## Verification

```bash
# Check Flux HelmReleases (all should be Ready: True)
flux get helmreleases -A

# Expected output:
# cert-manager                    ✓
# argo-workflows-crds             ✓
# external-secrets-crds           ✓
# registry                        ✓
# openchoreo-control-plane        ✓
# openchoreo-data-plane           ✓
# openchoreo-build-plane          ✓
# openchoreo-observability-plane  ✓

# Check Kustomizations
flux get kustomizations -A

# Check pods
kubectl get pods -A | grep -E "openchoreo|cert-manager"

# Check plane CRs
kubectl get dataplane,buildplane,observabilityplane -A
```

## Access URLs

- Console: http://openchoreovm.localhost:8080
- API: http://api.openchoreovm.localhost:8080
- Deployed apps: http://<env>.openchoreovm-apis.localhost:9080/<component>/...

**Default credentials:** `admin@openchoreo.dev` / `Admin@123`

## Configuration

Configuration values are stored in separate `values.yaml` files for each plane, loaded via ConfigMaps:

| Plane | Values File | Key Settings |
|-------|-------------|--------------|
| Control | `apps/openchoreo-control-plane/values.yaml` | baseDomain, gateway ports |
| Data | `apps/openchoreo-data-plane/values.yaml` | external-secrets, gateway |
| Build | `apps/openchoreo-build-plane/values.yaml` | registry host, argo workflows |
| Observability | `apps/openchoreo-observability-plane/values.yaml` | OpenSearch, Prometheus |

## Updating Versions

1. Update `chart.spec.version` in each HelmRelease
2. Commit and push
3. Flux automatically reconciles

```bash
# Force immediate reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system --with-source
```

## Troubleshooting

### HelmRelease stuck or failed

```bash
# Check HelmRelease status
flux get helmrelease <name> -n <namespace>

# View detailed events
kubectl describe helmrelease <name> -n <namespace>

# Check Helm controller logs
kubectl logs -n flux-system deploy/helm-controller

# Force reinstall
flux reconcile helmrelease <name> -n <namespace> --force
```

### CRD-related errors

If you see "no matches for kind ClusterWorkflowTemplate" or similar:
- Ensure `argo-workflows-crds` or `external-secrets-crds` HelmReleases are Ready
- Check that main releases have proper `dependsOn` referencing the CRD releases

## Cleanup

```bash
# Remove Flux and all managed resources
flux uninstall

# Or delete the k3d cluster entirely
k3d cluster delete openchoreo
```
