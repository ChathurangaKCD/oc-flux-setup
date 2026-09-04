#!/bin/bash
# Sync values YAML files from upstream OpenChoreo repository
# Usage: ./scripts/sync-values.sh [tag|commit]
# Example: ./scripts/sync-values.sh v1.0.0

set -e

# Configuration
UPSTREAM_REPO="openchoreo/openchoreo"
UPSTREAM_PATH="install/k3d/single-cluster"
UPSTREAM_COMMON_PATH="install/k3d/common"
DEFAULT_REF="v1.2.4"

# Domain replacements
UPSTREAM_DOMAIN="openchoreo.localhost"
LOCAL_DOMAIN="openchoreovm.test"
UPSTREAM_DP_DOMAIN="openchoreoapis.localhost"
LOCAL_DP_DOMAIN="openchoreoapis.openchoreovm.test"

# Control plane port (k3d maps host:18080 → container:8080, nginx-proxy proxies 8080→18080)
UPSTREAM_CP_HTTP_PORT_MAP="8080:8080"
LOCAL_CP_HTTP_PORT_MAP="18080:8080  # nginx-proxy on VM proxies 8080→18080 to strip HSTS/CSP headers"

# Target directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APPS_DIR="$REPO_ROOT/apps"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
REF="${1:-$DEFAULT_REF}"

echo -e "${GREEN}Syncing values from upstream OpenChoreo ${REF}${NC}"
echo "================================================"

# Function to fetch a file from a given upstream path and write transformed content
#
# IMPORTANT: We download to a temp file and apply transforms with `sed -i` instead of
# piping through `echo "$content" | sed ...`. Bash's `echo` (and many `printf`/`echo`
# implementations on Linux) interprets backslash escape sequences in some configurations.
# Files like values-thunder.yaml contain literal `\n` strings inside shell scripts (e.g.
# `tr '\n' ' '`). If those strings are echoed they get converted to actual newlines and
# the resulting YAML becomes unparseable. The temp-file approach avoids that entirely.
fetch_and_transform() {
    local upstream_path="$1"
    local upstream_file="$2"
    local local_file="$3"
    local plane_name="$4"

    local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${REF}/${upstream_path}/${upstream_file}"

    echo -e "${YELLOW}Fetching ${plane_name}...${NC}"
    echo "  URL: $url"

    # Fetch the file directly to disk (no shell variable round-trip)
    local tmp_file
    tmp_file=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp_file" 2>/dev/null; then
        echo -e "${RED}  ERROR: Failed to fetch ${upstream_file}${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    # Apply domain replacements in-place (preserves literal \n and other escape sequences)
    sed -i.bak "s/${UPSTREAM_DP_DOMAIN}/${LOCAL_DP_DOMAIN}/g" "$tmp_file"
    sed -i.bak "s/${UPSTREAM_DOMAIN}/${LOCAL_DOMAIN}/g" "$tmp_file"
    rm -f "${tmp_file}.bak"

    mv "$tmp_file" "$local_file"
    echo -e "${GREEN}  Written to: ${local_file}${NC}"
}

# Function to fetch and transform the k3d config file
fetch_and_transform_k3d_config() {
    local upstream_file="config.yaml"
    local local_file="$REPO_ROOT/k3d-config.yaml"

    local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${REF}/${UPSTREAM_PATH}/${upstream_file}"

    echo -e "${YELLOW}Fetching k3d config...${NC}"
    echo "  URL: $url"

    local tmp_file
    tmp_file=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp_file" 2>/dev/null; then
        echo -e "${RED}  ERROR: Failed to fetch ${upstream_file}${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    # Remap CP HTTP gateway port: 8080:8080 → 18080:8080 (so nginx-proxy can sit in front)
    sed -i.bak "s|port: ${UPSTREAM_CP_HTTP_PORT_MAP}|port: ${LOCAL_CP_HTTP_PORT_MAP}|g" "$tmp_file"
    rm -f "${tmp_file}.bak"

    mv "$tmp_file" "$local_file"
    echo -e "${GREEN}  Written to: ${local_file}${NC}"
}

# Fetch single-cluster values files
echo ""
fetch_and_transform "$UPSTREAM_PATH" "values-cp.yaml" \
    "$APPS_DIR/openchoreo-control-plane/values.yaml" "Control Plane"
echo ""
fetch_and_transform "$UPSTREAM_PATH" "values-dp.yaml" \
    "$APPS_DIR/openchoreo-data-plane/values.yaml" "Data Plane"
echo ""
fetch_and_transform "$UPSTREAM_PATH" "values-wp.yaml" \
    "$APPS_DIR/openchoreo-workflow-plane/values.yaml" "Workflow Plane"
echo ""
fetch_and_transform "$UPSTREAM_PATH" "values-registry.yaml" \
    "$APPS_DIR/openchoreo-workflow-plane/values-registry.yaml" "Registry"
echo ""
fetch_and_transform "$UPSTREAM_PATH" "values-op.yaml" \
    "$APPS_DIR/openchoreo-observability-plane/values.yaml" "Observability Plane"

# Fetch shared (common) values
echo ""
fetch_and_transform "$UPSTREAM_COMMON_PATH" "values-thunder.yaml" \
    "$APPS_DIR/thunder/values.yaml" "Thunder"

# Fetch k3d config
echo ""
fetch_and_transform_k3d_config

# Write version file
echo "${REF#v}" > "$REPO_ROOT/VERSION"
echo -e "${GREEN}Written version to: VERSION${NC}"

echo ""
echo "================================================"
echo -e "${GREEN}Sync complete!${NC}"
echo ""
echo "Replacements applied:"
echo "  Domains:"
echo "    ${UPSTREAM_DOMAIN} -> ${LOCAL_DOMAIN}"
echo "    ${UPSTREAM_DP_DOMAIN} -> ${LOCAL_DP_DOMAIN}"
echo "  k3d ports:"
echo "    ${UPSTREAM_CP_HTTP_PORT_MAP} -> 18080:8080 (control plane gateway, behind nginx-proxy)"
echo ""
echo "Note: Thunder bootstrap scripts contain hardcoded URLs (e.g. http://openchoreo.localhost:8080/...)"
echo "      that are auto-rewritten via sed. Verify with 'git diff apps/thunder/values.yaml'"
echo ""
echo "Review changes with: git diff"
echo "Commit with: git add -A && git commit -m 'Sync values from upstream ${REF}'"
