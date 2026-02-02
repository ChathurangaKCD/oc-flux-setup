# OpenChoreo Networking Architecture

This document explains how traffic flows from external clients to OpenChoreo services running on a k3d cluster.

## Overview

OpenChoreo runs on k3d (k3s in Docker). Traffic flows through multiple layers:

1. **VM Host** - External entry point
2. **k3d Load Balancer** - Docker container proxying ports
3. **Kubernetes Service** - LoadBalancer type service
4. **Gateway Pod** - Envoy-based Kubernetes Gateway API implementation
5. **HTTPRoute** - Host-based routing rules
6. **Backend Service** - Actual application pods

## Port Mappings

This VM only exposes ports 8080 and 9080 externally.

| External Port | nginx | k3d | Cluster Port | Purpose |
|---------------|-------|-----|--------------|---------|
| 8080 | ✓ | 18080 | 80 | Control Plane HTTP (UI, API) |
| 9080 | - | 9080 | 9080 | Data Plane HTTP (deployed workloads) |

**Traffic flow:**
- Control Plane: External → nginx (strips HSTS/CSP) → k3d → Cluster
- Data Plane: External → k3d → Cluster (no nginx needed)

See `k3d-config.yaml` for the full cluster configuration.

## Traffic Flow Example

Request: `http://api.openchoreovm.test:8080`

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Browser: http://api.openchoreovm.test:8080                                 │
│  (DNS resolves to VM IP via /etc/hosts)                                     │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  1. VM Host (e.g., 172.22.1.162:8080)                                       │
│     Port 8080 is bound by nginx-proxy container                             │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  2. nginx-proxy Container (host networking)                                 │
│     - Proxies 8080 → 18080 (control plane only)                             │
│     - Strips Strict-Transport-Security header                               │
│     - Strips Content-Security-Policy header (upgrade-insecure-requests)     │
│     - Data plane (9080) goes directly to k3d, no nginx needed               │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  3. k3d Load Balancer Container                                             │
│     Maps host port 18080 → cluster port 80                                  │
│     Forwards to k3d-openchoreo-server-0 node                                │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  3. LoadBalancer Service: gateway-default                                   │
│     Namespace: openchoreo-control-plane                                     │
│     Ports: 80:31608/TCP, 443:31697/TCP                                      │
│     External IP: 172.18.0.2 (k3d internal network)                          │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  4. Gateway Pod: gateway-default (Envoy proxy)                              │
│     Implements Kubernetes Gateway API                                       │
│     Reads HTTPRoute resources for routing decisions                         │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  5. HTTPRoute: Host header matching                                         │
│     ┌────────────────────────────────┬─────────────────────┬──────┐         │
│     │ HOSTNAME                       │ BACKEND SERVICE     │ PORT │         │
│     ├────────────────────────────────┼─────────────────────┼──────┤         │
│     │ api.openchoreovm.test       │ openchoreo-api      │ 8080 │ ◄───    │
│     │ openchoreovm.test           │ openchoreo-ui       │ 7007 │         │
│     │ thunder.openchoreovm.test   │ thunder-service     │ 8090 │         │
│     └────────────────────────────────┴─────────────────────┴──────┘         │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  6. Backend Service: openchoreo-api:8080                                    │
│     Routes to openchoreo-api pod                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## k3d Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  VM Host                                                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Docker Network: k3d-openchoreo (172.18.0.0/16)                     │    │
│  │                                                                     │    │
│  │  ┌─────────────────────────────────────────────────────────────┐    │    │
│  │  │  Container: k3d-openchoreo-serverlb                         │    │    │
│  │  │  - Binds to host ports: 18080, 9080                         │    │    │
│  │  │  - Forwards traffic to k3d-openchoreo-server-0              │    │    │
│  │  │  - Simple TCP proxy (nginx-based)                           │    │    │
│  │  └──────────────────────────┬──────────────────────────────────┘    │    │
│  │                             │                                       │    │
│  │                             ▼                                       │    │
│  │  ┌─────────────────────────────────────────────────────────────┐    │    │
│  │  │  Container: k3d-openchoreo-server-0 (172.18.0.2)            │    │    │
│  │  │  - Runs k3s (lightweight Kubernetes)                        │    │    │
│  │  │  - All pods run inside this container                       │    │    │
│  │  │  - LoadBalancer services get external IP 172.18.0.2         │    │    │
│  │  └─────────────────────────────────────────────────────────────┘    │    │
│  │                                                                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

### k3d-serverlb Container
- Created automatically by k3d based on `ports:` config
- Simple TCP proxy that forwards host ports to cluster
- No application-level routing (just port forwarding)

### gateway-default (Kgateway/Envoy)
- Kubernetes Gateway API implementation
- Performs host-based routing using HTTPRoute resources
- Handles TLS termination (when configured)

### HTTPRoute Resources
- Define routing rules based on Host header
- Map hostnames to backend services
- Support path-based routing, header matching, etc.

## Access URLs

After adding hosts entries pointing to the VM IP:

| URL | Service |
|-----|---------|
| http://openchoreovm.test:8080 | Backstage UI (Console) |
| http://api.openchoreovm.test:8080 | OpenChoreo API |
| http://thunder.openchoreovm.test:8080 | Thunder Service |
| http://*.dp.openchoreovm.test:9080 | Deployed Workloads |

### Local /etc/hosts Entry

```
<VM_IP> openchoreovm.test api.openchoreovm.test thunder.openchoreovm.test
```

**Default credentials:** `admin@openchoreo.dev` / `Admin@123`

## nginx Proxy

The nginx proxy is required for the **control plane only** to strip HSTS and CSP headers that break HTTP-only browser access. The data plane (Envoy) doesn't have these headers, so it connects directly to k3d.

**What nginx does:**
- Listens on port 8080 (external)
- Proxies to k3d on port 18080
- Strips `Strict-Transport-Security` header
- Strips `Content-Security-Policy` header (which includes `upgrade-insecure-requests`)

See [SETUP.md](SETUP.md#2-start-nginx-proxy) for installation instructions and [nginx-proxy.conf](nginx-proxy.conf) for the full configuration.

## Debugging Commands

```bash
# Check what's listening on host ports
ss -tlnp | grep -E "8080|9080|18080|19080"

# Check gateway service
kubectl get svc gateway-default -n openchoreo-control-plane

# Check HTTPRoutes
kubectl get httproute -n openchoreo-control-plane

# Check gateway pod logs
kubectl logs -n openchoreo-control-plane -l app.kubernetes.io/name=gateway-default

# Test routing from inside the VM
curl -s http://localhost:8080/ -H "Host: openchoreovm.test" | head -5

# Port-forward to test gateway directly
kubectl port-forward -n openchoreo-control-plane svc/gateway-default 9999:80
curl -s http://localhost:9999/ -H "Host: api.openchoreovm.test"

# Check k3d containers (requires docker access)
docker ps | grep k3d
```

## Troubleshooting

### Port 8080 returns 404
- Check if correct HTTPRoute exists for the hostname
- Verify the Host header matches exactly (including port if specified)
- Check gateway-default pod logs for routing errors

### Connection refused
- See [SETUP.md Troubleshooting](SETUP.md#troubleshooting) for port verification and nginx issues

### Traefik conflicts
The OpenChoreo k3d config disables traefik (`--disable=traefik`). If traefik is running:
```bash
kubectl delete deployment traefik -n kube-system
kubectl delete svc traefik -n kube-system
```
