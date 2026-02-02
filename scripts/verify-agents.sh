#!/bin/bash
# Verify cluster agent connections in OpenChoreo single-cluster setup
# Usage: ./scripts/verify-agents.sh
#
# This script checks that all plane agents are connected to the cluster-gateway.
# Run this after installation to verify inter-plane communication.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}OpenChoreo Agent Connection Verification${NC}"
echo "=========================================="
echo ""

# Function to check if namespace exists
namespace_exists() {
    kubectl get namespace "$1" &>/dev/null
}

# Function to check if pods exist with label
pods_exist() {
    local ns="$1"
    local label="$2"
    kubectl get pods -n "$ns" -l "$label" --no-headers 2>/dev/null | grep -q .
}

#------------------------------------------------------------------------------
# 1. Check Cluster Gateway (Control Plane)
#------------------------------------------------------------------------------
echo -e "${YELLOW}[1/4] Cluster Gateway (Control Plane)${NC}"
echo "--------------------------------------"

if namespace_exists "openchoreo-control-plane"; then
    echo -e "${GREEN}✓ Namespace exists${NC}"

    # Check gateway pods
    echo ""
    echo "Gateway pods:"
    kubectl get pods -n openchoreo-control-plane \
        -l app.kubernetes.io/component=cluster-gateway \
        -o wide 2>/dev/null || echo -e "${RED}  No cluster-gateway pods found${NC}"

    # Check gateway logs for agent connections
    if pods_exist "openchoreo-control-plane" "app.kubernetes.io/component=cluster-gateway"; then
        echo ""
        echo "Recent agent connection logs:"
        kubectl logs -n openchoreo-control-plane \
            -l app.kubernetes.io/component=cluster-gateway \
            --tail=30 2>/dev/null | grep -E "(agent registered|agent connected|certificate verification)" || \
            echo -e "${YELLOW}  No agent connection messages found in recent logs${NC}"
    fi
else
    echo -e "${RED}✗ Namespace openchoreo-control-plane not found${NC}"
fi

echo ""

#------------------------------------------------------------------------------
# 2. Check Data Plane Agent
#------------------------------------------------------------------------------
echo -e "${YELLOW}[2/4] Data Plane Agent${NC}"
echo "----------------------"

if namespace_exists "openchoreo-data-plane"; then
    echo -e "${GREEN}✓ Namespace exists${NC}"

    # Check agent pods
    echo ""
    echo "Agent pods:"
    kubectl get pods -n openchoreo-data-plane \
        -l app.kubernetes.io/component=cluster-agent \
        -o wide 2>/dev/null || echo -e "${RED}  No cluster-agent pods found${NC}"

    # Check agent logs
    if pods_exist "openchoreo-data-plane" "app.kubernetes.io/component=cluster-agent"; then
        echo ""
        echo "Recent agent logs:"
        kubectl logs -n openchoreo-data-plane \
            -l app.kubernetes.io/component=cluster-agent \
            --tail=20 2>/dev/null | grep -E "(connected|starting agent|error|ERROR)" || \
            echo -e "${YELLOW}  No connection messages found in recent logs${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Namespace openchoreo-data-plane not found (not installed)${NC}"
fi

echo ""

#------------------------------------------------------------------------------
# 3. Check Build Plane Agent
#------------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Build Plane Agent${NC}"
echo "-----------------------"

if namespace_exists "openchoreo-build-plane"; then
    echo -e "${GREEN}✓ Namespace exists${NC}"

    # Check agent pods
    echo ""
    echo "Agent pods:"
    kubectl get pods -n openchoreo-build-plane \
        -l app.kubernetes.io/component=cluster-agent \
        -o wide 2>/dev/null || echo -e "${RED}  No cluster-agent pods found${NC}"

    # Check agent logs
    if pods_exist "openchoreo-build-plane" "app.kubernetes.io/component=cluster-agent"; then
        echo ""
        echo "Recent agent logs:"
        kubectl logs -n openchoreo-build-plane \
            -l app.kubernetes.io/component=cluster-agent \
            --tail=20 2>/dev/null | grep -E "(connected|starting agent|error|ERROR)" || \
            echo -e "${YELLOW}  No connection messages found in recent logs${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Namespace openchoreo-build-plane not found (not installed)${NC}"
fi

echo ""

#------------------------------------------------------------------------------
# 4. Check Observability Plane Agent
#------------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Observability Plane Agent${NC}"
echo "--------------------------------"

if namespace_exists "openchoreo-observability-plane"; then
    echo -e "${GREEN}✓ Namespace exists${NC}"

    # Check agent pods
    echo ""
    echo "Agent pods:"
    kubectl get pods -n openchoreo-observability-plane \
        -l app.kubernetes.io/component=cluster-agent \
        -o wide 2>/dev/null || echo -e "${RED}  No cluster-agent pods found${NC}"

    # Check agent logs
    if pods_exist "openchoreo-observability-plane" "app.kubernetes.io/component=cluster-agent"; then
        echo ""
        echo "Recent agent logs:"
        kubectl logs -n openchoreo-observability-plane \
            -l app.kubernetes.io/component=cluster-agent \
            --tail=20 2>/dev/null | grep -E "(connected|starting agent|error|ERROR)" || \
            echo -e "${YELLOW}  No connection messages found in recent logs${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Namespace openchoreo-observability-plane not found (not installed)${NC}"
fi

echo ""

#------------------------------------------------------------------------------
# 5. Summary - Check Plane CRs
#------------------------------------------------------------------------------
echo -e "${YELLOW}[Summary] Registered Plane CRs${NC}"
echo "-------------------------------"
echo ""
echo "DataPlane resources:"
kubectl get dataplane -A 2>/dev/null || echo -e "${YELLOW}  No DataPlane CRs found${NC}"
echo ""
echo "BuildPlane resources:"
kubectl get buildplane -A 2>/dev/null || echo -e "${YELLOW}  No BuildPlane CRs found${NC}"
echo ""
echo "ObservabilityPlane resources:"
kubectl get observabilityplane -A 2>/dev/null || echo -e "${YELLOW}  No ObservabilityPlane CRs found${NC}"

echo ""
echo "=========================================="
echo -e "${GREEN}Verification complete${NC}"
echo ""
echo "Expected log messages for healthy connections:"
echo "  Gateway: 'agent registered', 'agent connected successfully'"
echo "  Agents:  'connected to control plane', 'starting agent'"
