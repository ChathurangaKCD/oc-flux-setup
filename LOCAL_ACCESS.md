# Accessing OpenChoreo Locally

This guide explains how to access OpenChoreo running on a remote VM from your local machine.

## Architecture

```
Local Browser → VM nginx (8080/9080) → k3d (18080/19080) → Kubernetes Cluster
```

The nginx proxy strips HSTS and CSP security headers that would otherwise force HTTPS and break HTTP-only browser access.

## Prerequisites

- OpenChoreo installed on the VM (see [README.md](README.md))
- VM IP address (e.g., `172.22.1.162`)

## 1. Configure /etc/hosts

Add entries to your local `/etc/hosts` file:

```bash
# Replace 172.22.1.162 with your VM's IP
sudo tee -a /etc/hosts << 'EOF'
172.22.1.162 openchoreovm.test api.openchoreovm.test thunder.openchoreovm.test development.dp.openchoreovm.test
EOF
```

For additional environments, add:
- `staging.dp.openchoreovm.test`
- `production.dp.openchoreovm.test`

### Wildcard DNS (Optional)

If you want wildcard support for `*.dp.openchoreovm.test`, use dnsmasq:

```bash
# macOS with Homebrew
brew install dnsmasq

# Configure wildcard
echo "address=/openchoreovm.test/172.22.1.162" | sudo tee /usr/local/etc/dnsmasq.d/openchoreo.conf

# Start dnsmasq
sudo brew services start dnsmasq

# Point .test domains to local dnsmasq
sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/test
```

## 2. Access URLs

| URL | Purpose | Port |
|-----|---------|------|
| http://openchoreovm.test:8080 | Console (UI) | Control Plane |
| http://api.openchoreovm.test:8080 | Management API | Control Plane |
| http://thunder.openchoreovm.test:8080 | Auth Service | Control Plane |
| http://development.dp.openchoreovm.test:9080 | Deployed Apps | Data Plane |

**Default credentials:** `admin@openchoreo.dev` / `Admin@123`

## 3. Test Connectivity

```bash
# Test control plane
curl -s http://openchoreovm.test:8080 | head -5

# Test API
curl -s http://api.openchoreovm.test:8080/api/v1/health

# Test deployed app (after deploying a component)
curl -s http://development.dp.openchoreovm.test:9080/greeter-service/greeter/greet
```

## Domain Structure

All domains are under `openchoreovm.test`:

```
openchoreovm.test
├── openchoreovm.test          → UI (Console)
├── api.openchoreovm.test      → Management API
├── thunder.openchoreovm.test  → Auth Service (Thunder)
└── dp.openchoreovm.test       → Data Plane (deployed workloads)
    ├── development.dp.openchoreovm.test
    ├── staging.dp.openchoreovm.test
    └── production.dp.openchoreovm.test
```

## Troubleshooting

### Browser shows blank page or HTTPS redirect

The nginx proxy may not be running. On the VM:

```bash
# Check nginx status
sudo docker ps | grep nginx-proxy

# Restart nginx proxy
curl -fsSL https://raw.githubusercontent.com/ChathurangaKCD/oc-flux-setup/main/nginx-proxy.conf -o /tmp/nginx-proxy.conf && \
  sudo docker rm -f nginx-proxy 2>/dev/null; \
  sudo docker run -d --name nginx-proxy --network host -v /tmp/nginx-proxy.conf:/etc/nginx/nginx.conf:ro nginx:alpine
```

### DNS not resolving

Verify `/etc/hosts` entry:

```bash
# Should return VM IP
ping -c 1 openchoreovm.test
```

### Connection refused

Check if ports are open on VM:

```bash
# From VM
ss -tlnp | grep -E "8080|9080"
```

### Clear browser HSTS cache

If you previously accessed the site with HSTS headers cached:

1. Go to `chrome://net-internals/#hsts`
2. Enter `openchoreovm.test` in "Delete domain security policies"
3. Click "Delete"
