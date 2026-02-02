#!/bin/bash
# OpenChoreo Bootstrap Script
# Fetches cluster config from GitHub and bootstraps k3d + Flux
#
# Prerequisites:
#   - docker, k3d, kubectl, flux CLI installed
#   - GITHUB_TOKEN environment variable exported
#
# Usage:
#   export GITHUB_TOKEN=<your-pat>
#   ./bootstrap.sh

set -euo pipefail

# Configuration
GITHUB_OWNER="ChathurangaKCD"
GITHUB_REPO="oc-flux-setup"
FLUX_PATH="clusters/openchoreo-dev"
CLUSTER_NAME="openchoreo"
K3D_CONFIG_URL="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/k3d-config.yaml"
NGINX_CONFIG_URL="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/nginx-proxy.conf"
NGINX_CONFIG_DIR="${HOME}/nginx-config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed"
        return 1
    fi
    log_success "$1 found"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local failed=0

    check_command docker || failed=1
    check_command k3d || failed=1
    check_command kubectl || failed=1
    check_command flux || failed=1
    check_command curl || failed=1

    if [ -z "${GITHUB_TOKEN:-}" ]; then
        log_error "GITHUB_TOKEN environment variable is not set"
        log_info "Please export your GitHub PAT: export GITHUB_TOKEN=<your-token>"
        failed=1
    else
        log_success "GITHUB_TOKEN is set"
    fi

    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        failed=1
    else
        log_success "Docker daemon is running"
    fi

    if [ $failed -eq 1 ]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Check if cluster already exists
check_existing_cluster() {
    if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}\s"; then
        log_warn "Cluster '${CLUSTER_NAME}' already exists"
        read -p "Do you want to delete it and start fresh? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing cluster..."
            k3d cluster delete "${CLUSTER_NAME}"
            log_success "Cluster deleted"
        else
            log_error "Aborting. Please delete the cluster manually or use a different name."
            exit 1
        fi
    fi
}

# Create k3d cluster
create_cluster() {
    log_info "Fetching k3d config from GitHub..."

    local config_file=$(mktemp)
    if ! curl -sSfL "${K3D_CONFIG_URL}" -o "${config_file}"; then
        log_error "Failed to fetch k3d config from ${K3D_CONFIG_URL}"
        rm -f "${config_file}"
        exit 1
    fi

    log_success "Config fetched successfully"
    log_info "Creating k3d cluster '${CLUSTER_NAME}'..."

    if ! k3d cluster create --config="${config_file}"; then
        log_error "Failed to create k3d cluster"
        rm -f "${config_file}"
        exit 1
    fi

    rm -f "${config_file}"
    log_success "Cluster created successfully"

    # Generate machine-id (required for FluentBit log collection in observability plane)
    log_info "Generating machine-id for k3d container..."
    if docker exec k3d-${CLUSTER_NAME}-server-0 sh -c "cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id"; then
        log_success "Machine-id generated"
    else
        log_warn "Failed to generate machine-id (FluentBit may not work correctly)"
    fi
}

# Setup nginx proxy
setup_nginx_proxy() {
    log_info "Setting up nginx proxy..."

    # Create persistent config directory
    mkdir -p "${NGINX_CONFIG_DIR}"

    # Download nginx config
    log_info "Fetching nginx config from GitHub..."
    if ! curl -sSfL "${NGINX_CONFIG_URL}" -o "${NGINX_CONFIG_DIR}/nginx-proxy.conf"; then
        log_error "Failed to fetch nginx config"
        exit 1
    fi

    # Remove existing container if any
    docker rm -f nginx-proxy 2>/dev/null || true

    # Start nginx with auto-restart
    log_info "Starting nginx proxy container..."
    if ! docker run -d --name nginx-proxy \
        --restart=always \
        --network host \
        -v "${NGINX_CONFIG_DIR}/nginx-proxy.conf:/etc/nginx/nginx.conf:ro" \
        nginx:alpine; then
        log_error "Failed to start nginx proxy"
        exit 1
    fi

    log_success "nginx proxy started (8080 → 18080)"
}

# Wait for cluster to be ready
wait_for_cluster() {
    log_info "Waiting for cluster to be ready..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
            log_success "Cluster is ready"
            return 0
        fi
        log_info "Waiting for node to be ready (attempt ${attempt}/${max_attempts})..."
        sleep 5
        ((attempt++))
    done

    log_error "Cluster did not become ready in time"
    exit 1
}

# Bootstrap Flux
bootstrap_flux() {
    log_info "Bootstrapping Flux..."

    # Check Flux prerequisites
    if ! flux check --pre; then
        log_error "Flux prerequisites check failed"
        exit 1
    fi

    log_info "Running flux bootstrap..."
    if ! flux bootstrap github \
        --owner="${GITHUB_OWNER}" \
        --repository="${GITHUB_REPO}" \
        --path="${FLUX_PATH}" \
        --personal \
        --token-auth; then
        log_error "Flux bootstrap failed"
        exit 1
    fi

    log_success "Flux bootstrapped successfully"
}

# Wait for Flux to reconcile
wait_for_flux() {
    log_info "Waiting for Flux to reconcile..."

    # Wait for flux-system kustomization to be ready
    log_info "Waiting for flux-system kustomization..."
    if ! kubectl wait --for=condition=Ready kustomization/flux-system -n flux-system --timeout=120s 2>/dev/null; then
        log_warn "flux-system kustomization not ready yet, continuing..."
    fi

    log_success "Flux is running"
}

# Show status
show_status() {
    echo
    log_info "============================================"
    log_info "Bootstrap Complete!"
    log_info "============================================"
    echo
    log_info "nginx proxy status:"
    docker ps --filter name=nginx-proxy --format "  {{.Names}}: {{.Status}}" 2>/dev/null || true
    echo
    log_info "Flux Kustomizations:"
    flux get kustomizations -A 2>/dev/null || true
    echo
    log_info "Flux HelmReleases:"
    flux get helmreleases -A 2>/dev/null || true
    echo
    log_info "============================================"
    log_info "Access URLs (once deployments are ready):"
    log_info "  Console: http://openchoreo.localhost:8080"
    log_info "  API:     http://api.openchoreo.localhost:8080"
    log_info "  Login:   admin@openchoreo.dev / Admin@123"
    log_info "============================================"
    log_info "Useful commands:"
    log_info "  flux get kustomizations -A"
    log_info "  flux get helmreleases -A"
    log_info "  kubectl get pods -A"
    log_info "============================================"
}

# Main
main() {
    echo
    log_info "============================================"
    log_info "OpenChoreo Bootstrap Script"
    log_info "============================================"
    echo

    check_prerequisites
    check_existing_cluster
    create_cluster
    wait_for_cluster
    setup_nginx_proxy
    bootstrap_flux
    wait_for_flux
    show_status
}

main "$@"
