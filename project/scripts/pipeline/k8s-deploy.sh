#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/k8s-deploy.log"
NAMESPACE="audit-system"
DEPLOYMENT_NAME="audit-system"
CONTAINER_NAME="audit-system"
IMAGE_TAG="$GIT_SHA"
ROLLOUT_TIMEOUT=300  # 5 minutes
HEALTH_CHECK_INTERVAL=10  # 10 seconds
MAX_RETRIES=30

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred on line $1"
    rollback_deployment
    exit 1
}

trap 'handle_error $LINENO' ERR

# Rollback deployment
rollback_deployment() {
    log "Initiating deployment rollback..."
    
    if ! kubectl rollout undo deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"; then
        log "ERROR: Rollback failed"
        return 1
    fi
    
    log "Rollback completed successfully"
    return 0
}

# Check deployment health
check_deployment_health() {
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}' | grep -q "^[1-9]"; then
            log "Deployment is healthy"
            return 0
        fi
        
        log "Waiting for deployment to become healthy... (Attempt $((retries + 1))/$MAX_RETRIES)"
        sleep "$HEALTH_CHECK_INTERVAL"
        retries=$((retries + 1))
    done
    
    log "ERROR: Deployment health check failed after $MAX_RETRIES attempts"
    return 1
}

# Update deployment
update_deployment() {
    log "Updating deployment..."
    
    # Update the deployment with new image
    if ! kubectl set image deployment/"$DEPLOYMENT_NAME" \
        "$CONTAINER_NAME=$DOCKER_REGISTRY/$IMAGE_NAME:$IMAGE_TAG" \
        -n "$NAMESPACE"; then
        log "ERROR: Failed to update deployment"
        return 1
    fi
    
    # Wait for rollout to complete
    log "Waiting for rollout to complete..."
    if ! kubectl rollout status deployment/"$DEPLOYMENT_NAME" \
        -n "$NAMESPACE" \
        --timeout="${ROLLOUT_TIMEOUT}s"; then
        log "ERROR: Rollout failed"
        return 1
    fi
    
    log "Deployment updated successfully"
    return 0
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check if all pods are running
    if ! kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" | grep -q "Running"; then
        log "ERROR: Not all pods are running"
        return 1
    fi
    
    # Check application health
    local service_url=$(kubectl get svc "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if ! curl -s "http://$service_url/health" | grep -q "ok"; then
        log "ERROR: Application health check failed"
        return 1
    fi
    
    log "Deployment verification completed successfully"
    return 0
}

# Main execution
log "Starting Kubernetes deployment process..."

# Update deployment
if ! update_deployment; then
    rollback_deployment
    exit 1
fi

# Check deployment health
if ! check_deployment_health; then
    rollback_deployment
    exit 1
fi

# Verify deployment
if ! verify_deployment; then
    rollback_deployment
    exit 1
fi

log "Kubernetes deployment completed successfully" 