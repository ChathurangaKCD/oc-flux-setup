#!/bin/bash
# Sync values YAML files from upstream OpenChoreo repository
# Usage: ./scripts/sync-values.sh [tag|commit]
# Example: ./scripts/sync-values.sh v0.12.0

set -e

# Configuration
UPSTREAM_REPO="openchoreo/openchoreo"
UPSTREAM_PATH="install/k3d/single-cluster"
DEFAULT_REF="v0.12.0"

# Domain replacements
UPSTREAM_DOMAIN="openchoreo.localhost"
LOCAL_DOMAIN="openchoreovm.test"
UPSTREAM_DP_DOMAIN="openchoreoapis.localhost"
LOCAL_DP_DOMAIN="dp.openchoreovm.test"

# Port replacements (simplify external port to match internal)
UPSTREAM_DP_HTTP_PORT="19080"
LOCAL_DP_HTTP_PORT="9080"
UPSTREAM_DP_HTTPS_PORT="19443"
LOCAL_DP_HTTPS_PORT="9443"

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

# Function to fetch and transform a values file
fetch_and_transform() {
    local upstream_file="$1"
    local local_file="$2"
    local plane_name="$3"

    local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${REF}/${UPSTREAM_PATH}/${upstream_file}"

    echo -e "${YELLOW}Fetching ${plane_name}...${NC}"
    echo "  URL: $url"

    # Fetch the file
    local content
    if ! content=$(curl -fsSL "$url" 2>/dev/null); then
        echo -e "${RED}  ERROR: Failed to fetch ${upstream_file}${NC}"
        return 1
    fi

    # Apply domain replacements
    content=$(echo "$content" | sed "s/${UPSTREAM_DOMAIN}/${LOCAL_DOMAIN}/g")
    content=$(echo "$content" | sed "s/${UPSTREAM_DP_DOMAIN}/${LOCAL_DP_DOMAIN}/g")

    # Apply port replacements (data plane ports)
    content=$(echo "$content" | sed "s/${UPSTREAM_DP_HTTP_PORT}/${LOCAL_DP_HTTP_PORT}/g")
    content=$(echo "$content" | sed "s/${UPSTREAM_DP_HTTPS_PORT}/${LOCAL_DP_HTTPS_PORT}/g")

    # Write to local file
    echo "$content" > "$local_file"
    echo -e "${GREEN}  Written to: ${local_file}${NC}"
}

# Fetch each values file
echo ""
fetch_and_transform "values-cp.yaml" "$APPS_DIR/openchoreo-control-plane/values.yaml" "Control Plane"
echo ""
fetch_and_transform "values-dp.yaml" "$APPS_DIR/openchoreo-data-plane/values.yaml" "Data Plane"
echo ""
fetch_and_transform "values-bp.yaml" "$APPS_DIR/openchoreo-build-plane/values.yaml" "Build Plane"
echo ""
fetch_and_transform "values-op.yaml" "$APPS_DIR/openchoreo-observability-plane/values.yaml" "Observability Plane"

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
echo "  Ports:"
echo "    ${UPSTREAM_DP_HTTP_PORT} -> ${LOCAL_DP_HTTP_PORT}"
echo "    ${UPSTREAM_DP_HTTPS_PORT} -> ${LOCAL_DP_HTTPS_PORT}"
echo ""
echo "Review changes with: git diff"
echo "Commit with: git add -A && git commit -m 'Sync values from upstream ${REF}'"
