# OpenChoreo 0.11 Flux GitOps Setup

This repository contains Flux GitOps manifests for deploying OpenChoreo 0.11 on a k3d cluster.

## Repository Structure

```
oc-flux-setup/
├── clusters/
│   └── openchoreo-dev/
│       └── kustomization.yaml       # Entry point - references infrastructure + apps
├── infrastructure/
│   ├── sources/
│   │   └── helm-repositories.yaml   # Helm repos (jetstack + openchoreo OCI)
│   ├── cert-manager/
│   │   ├── namespace.yaml
│   │   └── helmrelease.yaml
│   └── kustomization.yaml
└── apps/
    └── openchoreo/
        ├── namespaces.yaml          # All OpenChoreo namespaces
        ├── control-plane.yaml       # HelmRelease + TLS Certificate
        ├── data-plane.yaml          # HelmRelease + Certificate + DataPlane CR
        ├── build-plane.yaml         # HelmRelease + BuildPlane CR
        ├── observability-plane.yaml # HelmRelease + ObservabilityPlane CR
        └── kustomization.yaml
```

## Dependency Chain

```
cert-manager
    └── control-plane
            ├── data-plane
            ├── build-plane
            └── observability-plane
```

## Prerequisites

- k3d cluster running (see below)
- Flux CLI installed
- GitHub repository created

### Create k3d Cluster

```bash
curl -s https://raw.githubusercontent.com/openchoreo/openchoreo/release-v0.11/install/k3d/single-cluster/config.yaml | k3d cluster create --config=-
```

## Installation

### Option 1: Bootstrap with Flux (Recommended)

```bash
# Bootstrap Flux and connect to this repository
flux bootstrap github \
  --owner=<your-github-user> \
  --repository=oc-flux-setup \
  --path=clusters/openchoreo-dev \
  --personal
```

### Option 2: Manual Apply (Testing)

```bash
# Install Flux components first
flux install

# Apply the manifests
kubectl apply -k clusters/openchoreo-dev/
```

## Verification

```bash
# Check Flux HelmReleases
flux get helmreleases -A

# Check pods
kubectl get pods -n cert-manager
kubectl get pods -n openchoreo-control-plane
kubectl get pods -n openchoreo-data-plane
kubectl get pods -n openchoreo-build-plane
kubectl get pods -n openchoreo-observability-plane

# Check plane CRs
kubectl get dataplane,buildplane,observabilityplane -A
```

## Access URLs

- Console: http://openchoreo.localhost:8080
- API: http://api.openchoreo.localhost:8080
- Deployed apps: http://<env>.openchoreoapis.localhost:19080/<component>/...

**Default credentials:** `admin@openchoreo.dev` / `Admin@123`

## Configuration

### Control Plane
- Base domain: `openchoreo.localhost`
- Port: `:8080`
- Gateway ports: 80/443

### Data Plane
- Gateway ports: 19080/19443
- External secrets: enabled
- Gateway controller: disabled

### Build Plane
- Registry: `host.k3d.internal:10082`
- Argo workflows: enabled

### Observability Plane
- OpenSearch: enabled (standalone mode)

## Updating Versions

To update OpenChoreo version, modify the `chart.spec.version` in each HelmRelease file:

```yaml
spec:
  chart:
    spec:
      version: "0.12.0"  # Update version here
```

Flux will automatically reconcile the changes.

## Cleanup

```bash
# Remove Flux and all managed resources
flux uninstall

# Or delete the k3d cluster entirely
k3d cluster delete openchoreo
```
