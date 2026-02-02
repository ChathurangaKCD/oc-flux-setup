# OpenChoreo Setup Guide

Detailed instructions for setting up OpenChoreo on a k3d cluster using Flux GitOps.

## Quick Start

Bootstrap everything with a single command:

```bash
export GITHUB_TOKEN=<your-github-pat>
curl -fsSL https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/scripts/bootstrap.sh | bash
```

This will:
- Create the k3d cluster with the correct configuration
- Generate machine-id for FluentBit log collection
- Start nginx proxy for control plane access
- Bootstrap Flux GitOps

## Prerequisites

- k3d v5.8+
- kubectl v1.32+
- Flux CLI v2.0+
- Docker with host networking support
- GitHub personal access token (for Flux bootstrap)

## Architecture

### Dependency Chain

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

### CRD Pre-Installation

The build-plane and data-plane charts have **post-install hooks** that reference CRDs installed by the chart itself. Helm fails because hooks are processed before CRDs are registered.

**Solution:** Pre-install CRDs using separate HelmReleases:
- `argo-workflows-crds` - Installs only Argo CRDs (controller/server disabled)
- `external-secrets-crds` - Installs only ESO CRDs (operator disabled)

## Installation

### 1. Create k3d Cluster

```bash
# Download and create cluster with the included config
curl -fsSL https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/k3d-config.yaml -o /tmp/k3d-config.yaml
sudo k3d cluster create --config=/tmp/k3d-config.yaml

# Set up kubeconfig
mkdir -p ~/.kube && sudo k3d kubeconfig get openchoreo > ~/.kube/config && chmod 600 ~/.kube/config

# Generate machine-id (required for FluentBit log collection)
sudo docker exec k3d-openchoreo-server-0 sh -c "cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id"
```

### 2. Start nginx Proxy

The nginx proxy strips HSTS and CSP headers from the control plane (Backstage UI) that would otherwise force HTTPS.

```bash
# Create persistent config directory
mkdir -p ~/nginx-config

# Download config to persistent location (survives reboots)
curl -fsSL https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/nginx-proxy.conf -o ~/nginx-config/nginx-proxy.conf

# Start nginx with auto-restart policy
sudo docker rm -f nginx-proxy 2>/dev/null
sudo docker run -d --name nginx-proxy \
  --restart=always \
  --network host \
  -v ~/nginx-config/nginx-proxy.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
```

**Port mapping:**
- Control plane: `8080 → nginx → 18080 → k3d → 80`
- Data plane: `9080 → k3d → 9080` (direct, no nginx needed)

> **Note:** Using `--restart=always` ensures nginx automatically restarts after VM reboots. The config is stored in `~/nginx-config/` instead of `/tmp/` to persist across reboots.

### 3. Bootstrap Flux

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

# Expected: 8 releases all Ready
# - cert-manager
# - argo-workflows-crds
# - external-secrets-crds
# - registry
# - openchoreo-control-plane
# - openchoreo-data-plane
# - openchoreo-build-plane
# - openchoreo-observability-plane

# Check Kustomizations
flux get kustomizations -A

# Check pods
kubectl get pods -A | grep -E "openchoreo|cert-manager"

# Check plane CRs
kubectl get dataplane,buildplane,observabilityplane -A
```

## Configuration

### Values Files

Configuration is stored in `values.yaml` files, loaded via ConfigMaps:

| Plane | Values File | Key Settings |
|-------|-------------|--------------|
| Control | `apps/openchoreo-control-plane/values.yaml` | baseDomain, gateway ports |
| Data | `apps/openchoreo-data-plane/values.yaml` | external-secrets, gateway ports |
| Build | `apps/openchoreo-build-plane/values.yaml` | registry host, argo workflows |
| Observability | `apps/openchoreo-observability-plane/values.yaml` | OpenSearch, Prometheus |

### Plane CRs

The `apps/openchoreo-plane-crs/plane-registrations.yaml` defines:
- **DataPlane** - Gateway ports and virtual hosts
- **BuildPlane** - Cluster agent configuration
- **ObservabilityPlane** - Observer URL

## Updating Versions

### Automatic (GitHub Action)

The repo includes a GitHub Action that checks for new upstream releases and syncs automatically. See the workflow at `.github/workflows/sync-upstream.yaml`.

### Manual Sync

```bash
# Sync from a specific tag
./scripts/sync-values.sh v0.12.0

# Review changes
git diff

# Commit
git add -A && git commit -m "Sync values from upstream v0.12.0"
git push
```

### Update Chart Versions

1. Update `chart.spec.version` in each HelmRelease under `apps/*/helmrelease.yaml`
2. Commit and push
3. Flux automatically reconciles

```bash
# Force immediate reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system --with-source
```

## VM Restart Recovery

After a VM restart, the k3d cluster containers restart automatically but may take time to become healthy. If kubectl stops responding:

### Manual Recovery

```bash
# Check k3d container status
docker ps -a --filter name=k3d

# Restart the k3d cluster
k3d cluster stop openchoreo && k3d cluster start openchoreo

# Clean up any pods stuck in Unknown state
kubectl delete pods -A --field-selector=status.phase=Unknown --force --grace-period=0
```

### Automatic Recovery (Optional)

Install a systemd service that automatically recovers the cluster after VM restart:

```bash
# Download the recovery script
sudo curl -fsSL https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/scripts/k3d-recovery.sh -o /usr/local/bin/k3d-recovery.sh
sudo chmod +x /usr/local/bin/k3d-recovery.sh

# Create log file
sudo touch /var/log/k3d-recovery.log
sudo chown $USER:$USER /var/log/k3d-recovery.log

# Install systemd service
sudo tee /etc/systemd/system/k3d-recovery.service > /dev/null <<EOF
[Unit]
Description=k3d Cluster Auto-Recovery Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=$USER
ExecStart=/usr/local/bin/k3d-recovery.sh
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable k3d-recovery.service
```

The recovery script:
- Waits for Docker to be ready
- Checks cluster health every 60 seconds (up to 5 attempts)
- Automatically restarts k3d if cluster doesn't recover
- Logs to `/var/log/k3d-recovery.log`

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

### Connection refused / ports not listening

Verify the expected ports are open:

```bash
ss -tlnp | grep -E "8080|9080|18080"
```

Expected:
- `8080` - nginx proxy (control plane)
- `9080` - k3d data plane
- `18080` - k3d control plane (behind nginx)

### nginx proxy issues

```bash
# Check nginx status
docker ps | grep nginx-proxy

# View nginx logs
docker logs nginx-proxy

# Restart nginx
docker restart nginx-proxy

# If nginx container is missing after reboot, recreate it:
docker run -d --name nginx-proxy \
  --restart=always \
  --network host \
  -v ~/nginx-config/nginx-proxy.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
```

### Browser HSTS cache

If the browser still redirects to HTTPS after setting up nginx:
1. Go to `chrome://net-internals/#hsts`
2. Enter `openchoreovm.test` in "Delete domain security policies"
3. Click "Delete"

## Cleanup

```bash
# Remove Flux and all managed resources
flux uninstall

# Stop nginx proxy
sudo docker rm -f nginx-proxy

# Delete the k3d cluster
sudo k3d cluster delete openchoreo
```

## Related Documentation

- [README.md](README.md) - Overview and quick start
- [LOCAL_ACCESS.md](LOCAL_ACCESS.md) - Accessing from local machine
- [networking.md](networking.md) - Network architecture details
