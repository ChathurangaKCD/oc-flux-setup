#!/bin/bash
# k3d cluster auto-recovery script
# Runs after VM restart to ensure k3d cluster is healthy

LOG_FILE="/var/log/k3d-recovery.log"
CLUSTER_NAME="openchoreo"
MAX_ATTEMPTS=5
INTERVAL_SECONDS=60

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_cluster_health() {
    # Check if kubectl can connect and get nodes
    if kubectl get nodes --request-timeout=10s &>/dev/null; then
        # Check if node is Ready
        if kubectl get nodes | grep -q "Ready"; then
            return 0
        fi
    fi
    return 1
}

restart_k3d_cluster() {
    log "Attempting to restart k3d cluster..."

    # Stop the cluster
    k3d cluster stop "$CLUSTER_NAME" 2>&1 | tee -a "$LOG_FILE"
    sleep 5

    # Start the cluster
    k3d cluster start "$CLUSTER_NAME" 2>&1 | tee -a "$LOG_FILE"
    sleep 10

    # Clean up any pods stuck in Unknown state
    log "Cleaning up stale pods..."
    for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        kubectl delete pods -n "$ns" --field-selector=status.phase=Unknown --force --grace-period=0 2>/dev/null
    done
}

main() {
    log "=========================================="
    log "k3d recovery script started"
    log "Cluster: $CLUSTER_NAME"
    log "Max attempts: $MAX_ATTEMPTS"
    log "Interval: ${INTERVAL_SECONDS}s"
    log "=========================================="

    # Wait for Docker to be ready
    log "Waiting for Docker daemon..."
    for i in {1..30}; do
        if docker info &>/dev/null; then
            log "Docker is ready"
            break
        fi
        sleep 2
    done

    if ! docker info &>/dev/null; then
        log "ERROR: Docker daemon not available after 60s"
        exit 1
    fi

    # Check if k3d cluster exists
    if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
        log "ERROR: Cluster '$CLUSTER_NAME' not found"
        exit 1
    fi

    # Check cluster health with retries
    for attempt in $(seq 1 $MAX_ATTEMPTS); do
        log "Health check attempt $attempt/$MAX_ATTEMPTS..."

        if check_cluster_health; then
            log "SUCCESS: Cluster is healthy!"

            # Log pod status summary
            log "Pod status summary:"
            kubectl get pods -A --no-headers 2>/dev/null | awk '{print $4}' | sort | uniq -c | while read count status; do
                log "  $status: $count"
            done

            exit 0
        fi

        log "Cluster not ready yet"

        if [ $attempt -lt $MAX_ATTEMPTS ]; then
            log "Waiting ${INTERVAL_SECONDS}s before next check..."
            sleep $INTERVAL_SECONDS
        fi
    done

    # Cluster didn't recover naturally, attempt restart
    log "WARNING: Cluster did not recover after $MAX_ATTEMPTS attempts"
    log "Initiating automatic recovery..."

    restart_k3d_cluster

    # Final health check after restart
    log "Waiting 30s for cluster to stabilize after restart..."
    sleep 30

    if check_cluster_health; then
        log "SUCCESS: Cluster recovered after restart!"
        exit 0
    else
        log "ERROR: Cluster still unhealthy after restart. Manual intervention required."
        exit 1
    fi
}

main "$@"
