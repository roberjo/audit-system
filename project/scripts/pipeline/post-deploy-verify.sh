#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/post-deploy.log"
NAMESPACE="audit-system"
DEPLOYMENT_NAME="audit-system"
SERVICE_NAME="audit-system"
HEALTH_CHECK_ENDPOINTS=("/health" "/health/db" "/health/cache" "/health/queue")
PERFORMANCE_THRESHOLD=1000  # milliseconds
ERROR_RATE_THRESHOLD=0.01  # 1%

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Get service URL
get_service_url() {
    local url
    url=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$url" ]; then
        log "ERROR: Could not determine service URL"
        return 1
    fi
    echo "http://$url"
}

# Check endpoint health
check_endpoint_health() {
    local base_url=$1
    local endpoint=$2
    local url="${base_url}${endpoint}"
    
    log "Checking endpoint: $endpoint"
    
    if ! curl -s -f "$url" > /dev/null; then
        log "ERROR: Endpoint $endpoint is not healthy"
        return 1
    fi
    
    log "Endpoint $endpoint is healthy"
    return 0
}

# Check performance
check_performance() {
    local base_url=$1
    local endpoint=$2
    local url="${base_url}${endpoint}"
    
    log "Checking performance for endpoint: $endpoint"
    
    local start_time=$(date +%s%N)
    curl -s "$url" > /dev/null
    local end_time=$(date +%s%N)
    
    local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [ "$duration" -gt "$PERFORMANCE_THRESHOLD" ]; then
        log "WARNING: Endpoint $endpoint response time ($duration ms) exceeds threshold ($PERFORMANCE_THRESHOLD ms)"
        return 1
    fi
    
    log "Endpoint $endpoint performance is acceptable ($duration ms)"
    return 0
}

# Check error rates
check_error_rates() {
    local base_url=$1
    
    log "Checking error rates..."
    
    # Get logs from the last 5 minutes
    local error_count=$(kubectl logs -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" --since=5m | grep -c "ERROR")
    local total_requests=$(kubectl logs -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" --since=5m | grep -c "Request")
    
    if [ "$total_requests" -eq 0 ]; then
        log "WARNING: No requests found in logs"
        return 0
    fi
    
    local error_rate=$(echo "scale=4; $error_count / $total_requests" | bc)
    
    if (( $(echo "$error_rate > $ERROR_RATE_THRESHOLD" | bc -l) )); then
        log "ERROR: Error rate ($error_rate) exceeds threshold ($ERROR_RATE_THRESHOLD)"
        return 1
    fi
    
    log "Error rate is acceptable ($error_rate)"
    return 0
}

# Check resource usage
check_resource_usage() {
    log "Checking resource usage..."
    
    # Check CPU usage
    local cpu_usage=$(kubectl top pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" | awk 'NR>1 {print $3}' | sed 's/%//')
    for usage in $cpu_usage; do
        if [ "$usage" -gt 80 ]; then
            log "WARNING: High CPU usage detected: $usage%"
            return 1
        fi
    done
    
    # Check memory usage
    local memory_usage=$(kubectl top pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" | awk 'NR>1 {print $4}' | sed 's/Mi//')
    for usage in $memory_usage; do
        if [ "$usage" -gt 1000 ]; then
            log "WARNING: High memory usage detected: $usage Mi"
            return 1
        fi
    done
    
    log "Resource usage is acceptable"
    return 0
}

# Main execution
log "Starting post-deployment verification..."

# Get service URL
SERVICE_URL=$(get_service_url)
if [ $? -ne 0 ]; then
    exit 1
fi

# Check all health endpoints
for endpoint in "${HEALTH_CHECK_ENDPOINTS[@]}"; do
    if ! check_endpoint_health "$SERVICE_URL" "$endpoint"; then
        exit 1
    fi
done

# Check performance for main endpoints
for endpoint in "${HEALTH_CHECK_ENDPOINTS[@]}"; do
    if ! check_performance "$SERVICE_URL" "$endpoint"; then
        log "WARNING: Performance check failed for $endpoint"
    fi
done

# Check error rates
if ! check_error_rates "$SERVICE_URL"; then
    exit 1
fi

# Check resource usage
if ! check_resource_usage; then
    log "WARNING: Resource usage check failed"
fi

log "Post-deployment verification completed successfully" 