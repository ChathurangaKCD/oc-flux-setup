# OpenChoreo Flux GitOps Setup

Flux GitOps manifests for deploying [OpenChoreo](https://github.com/openchoreo/openchoreo) on a k3d cluster running on a remote VM.

## What This Repo Does

- **Deploys OpenChoreo** using Flux GitOps with all four planes (control, data, build, observability)
- **Auto-syncs with upstream** - GitHub Action checks for new OpenChoreo releases and updates values automatically
- **Handles k3d/VM quirks** - Custom domain/port configuration and nginx proxy to strip HSTS headers for HTTP access

## Current Version

![Version](https://img.shields.io/badge/dynamic/regex?url=https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/VERSION&search=.*&label=OpenChoreo&color=blue)

See [VERSION](VERSION) file for the currently synced upstream version.

## Auto-Sync with Upstream

A GitHub Action runs hourly on Fri/Sat to:
1. Check latest [OpenChoreo release](https://github.com/openchoreo/openchoreo/releases)
2. Compare with current VERSION
3. If newer, run `sync-values.sh` to update values and commit

This keeps the repo in sync with upstream without manual intervention.

**Manual sync:**
```bash
./scripts/sync-values.sh v0.12.0
```

The script fetches upstream values and applies replacements:
| Upstream | This Repo |
|----------|-----------|
| `openchoreo.localhost` | `openchoreovm.test` |
| `openchoreoapis.localhost` | `dp.openchoreovm.test` |
| Port `19080` | Port `9080` |

## Quick Start

See [SETUP.md](SETUP.md) for full installation instructions.

```bash
# 1. Create k3d cluster
sudo k3d cluster create --config=k3d-config.yaml

# 2. Start nginx proxy (strips HSTS headers for HTTP access)
curl -fsSL https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/nginx-proxy.conf -o /tmp/nginx-proxy.conf && \
  sudo docker run -d --name nginx-proxy --network host -v /tmp/nginx-proxy.conf:/etc/nginx/nginx.conf:ro nginx:alpine

# 3. Bootstrap Flux
export GITHUB_TOKEN=<your-pat>
flux bootstrap github --owner=<user> --repository=oc-flux-setup --path=clusters/openchoreo-dev --personal --token-auth
```

## Access

See [LOCAL_ACCESS.md](LOCAL_ACCESS.md) for accessing from your local machine.

| URL | Purpose |
|-----|---------|
| http://openchoreovm.test:8080 | Console (UI) |
| http://api.openchoreovm.test:8080 | Management API |
| http://development.dp.openchoreovm.test:9080 | Deployed Apps |

**Credentials:** `admin@openchoreo.dev` / `Admin@123`

## Repository Structure

```
oc-flux-setup/
├── clusters/openchoreo-dev/     # Flux Kustomizations (entry point)
├── infrastructure/              # cert-manager, helm repositories
├── apps/
│   ├── openchoreo-control-plane/
│   ├── openchoreo-data-plane/
│   ├── openchoreo-build-plane/
│   ├── openchoreo-observability-plane/
│   └── openchoreo-plane-crs/    # DataPlane, BuildPlane, ObservabilityPlane CRs
├── scripts/
│   └── sync-values.sh           # Sync values from upstream
├── k3d-config.yaml              # k3d cluster config
├── nginx-proxy.conf             # nginx config for HTTP access
├── VERSION                      # Current synced version
├── SETUP.md                     # Detailed setup instructions
└── LOCAL_ACCESS.md              # Local access guide
```

## Documentation

- [SETUP.md](SETUP.md) - Full installation and configuration guide
- [LOCAL_ACCESS.md](LOCAL_ACCESS.md) - Accessing OpenChoreo from your local machine
- [networking.md](networking.md) - Network architecture details
