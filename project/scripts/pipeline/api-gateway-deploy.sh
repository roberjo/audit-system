#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/api-gateway-deploy.log"
API_NAME="audit-system-api"
STAGE_BLUE="blue"
STAGE_GREEN="green"
LANE_BLUE="blue"
LANE_GREEN="green"
REGION="us-east-1"
APPROVAL_TIMEOUT=3600  # 1 hour in seconds
HEALTH_CHECK_INTERVAL=30  # 30 seconds
MAX_RETRIES=20

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

# Get API Gateway ID
get_api_id() {
    log "Getting API Gateway ID..."
    
    local api_id
    api_id=$(aws apigateway get-rest-apis --region "$REGION" --query "items[?name=='$API_NAME'].id" --output text)
    
    if [ -z "$api_id" ]; then
        log "ERROR: API Gateway not found"
        return 1
    fi
    
    echo "$api_id"
    return 0
}

# Determine active and inactive stages
determine_stages() {
    local api_id=$1
    log "Determining active and inactive stages..."
    
    # Get stage variables
    local blue_lane
    local green_lane
    
    blue_lane=$(aws apigateway get-stage \
        --rest-api-id "$api_id" \
        --stage-name "$STAGE_BLUE" \
        --region "$REGION" \
        --query "variables.lane" \
        --output text)
    
    green_lane=$(aws apigateway get-stage \
        --rest-api-id "$api_id" \
        --stage-name "$STAGE_GREEN" \
        --region "$REGION" \
        --query "variables.lane" \
        --output text)
    
    # Determine active stage
    if [ "$blue_lane" = "active" ]; then
        ACTIVE_STAGE=$STAGE_BLUE
        INACTIVE_STAGE=$STAGE_GREEN
        ACTIVE_LANE=$LANE_BLUE
        INACTIVE_LANE=$LANE_GREEN
    elif [ "$green_lane" = "active" ]; then
        ACTIVE_STAGE=$STAGE_GREEN
        INACTIVE_STAGE=$STAGE_BLUE
        ACTIVE_LANE=$LANE_GREEN
        INACTIVE_LANE=$LANE_BLUE
    else
        log "ERROR: No active stage found"
        return 1
    fi
    
    log "Active stage: $ACTIVE_STAGE ($ACTIVE_LANE)"
    log "Inactive stage: $INACTIVE_STAGE ($INACTIVE_LANE)"
    return 0
}

# Deploy to inactive stage
deploy_to_inactive() {
    local api_id=$1
    log "Deploying to inactive stage: $INACTIVE_STAGE"
    
    # Create new deployment
    local deployment_id
    deployment_id=$(aws apigateway create-deployment \
        --rest-api-id "$api_id" \
        --stage-name "$INACTIVE_STAGE" \
        --region "$REGION" \
        --query "id" \
        --output text)
    
    if [ -z "$deployment_id" ]; then
        log "ERROR: Failed to create deployment"
        return 1
    fi
    
    log "Deployment created with ID: $deployment_id"
    return 0
}

# Wait for deployment
wait_for_deployment() {
    local api_id=$1
    local deployment_id=$2
    log "Waiting for deployment to complete..."
    
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        local status
        status=$(aws apigateway get-deployment \
            --rest-api-id "$api_id" \
            --deployment-id "$deployment_id" \
            --region "$REGION" \
            --query "status" \
            --output text)
        
        if [ "$status" = "DEPLOYED" ]; then
            log "Deployment completed successfully"
            return 0
        fi
        
        log "Deployment in progress... (Attempt $((retries + 1))/$MAX_RETRIES)"
        sleep "$HEALTH_CHECK_INTERVAL"
        retries=$((retries + 1))
    done
    
    log "ERROR: Deployment timed out"
    return 1
}

# Wait for approval
wait_for_approval() {
    log "Waiting for approval..."
    log "Please review the deployment and approve by creating file: ../artifacts/approve_deployment"
    
    local start_time=$(date +%s)
    while true; do
        if [ -f "../artifacts/approve_deployment" ]; then
            log "Deployment approved"
            rm "../artifacts/approve_deployment"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $APPROVAL_TIMEOUT ]; then
            log "ERROR: Approval timeout"
            return 1
        fi
        
        sleep 10
    done
}

# Swap stages
swap_stages() {
    local api_id=$1
    log "Swapping stages..."
    
    # Update stage variables
    if ! aws apigateway update-stage \
        --rest-api-id "$api_id" \
        --stage-name "$ACTIVE_STAGE" \
        --patch-operations op=replace,path=/variables/lane,value="inactive" \
        --region "$REGION"; then
        log "ERROR: Failed to update active stage variables"
        return 1
    fi
    
    if ! aws apigateway update-stage \
        --rest-api-id "$api_id" \
        --stage-name "$INACTIVE_STAGE" \
        --patch-operations op=replace,path=/variables/lane,value="active" \
        --region "$REGION"; then
        log "ERROR: Failed to update inactive stage variables"
        return 1
    fi
    
    log "Stages swapped successfully"
    return 0
}

# Verify deployment
verify_deployment() {
    local api_id=$1
    log "Verifying deployment..."
    
    # Check if new active stage is accessible
    local new_active_url
    new_active_url=$(aws apigateway get-stage \
        --rest-api-id "$api_id" \
        --stage-name "$INACTIVE_STAGE" \
        --region "$REGION" \
        --query "variables.lane" \
        --output text)
    
    if [ "$new_active_url" != "active" ]; then
        log "ERROR: New active stage not properly configured"
        return 1
    fi
    
    log "Deployment verified successfully"
    return 0
}

# Main execution
log "Starting API Gateway Blue/Green deployment..."

# Get API Gateway ID
API_ID=$(get_api_id)
if [ $? -ne 0 ]; then
    exit 1
fi

# Determine active and inactive stages
if ! determine_stages "$API_ID"; then
    exit 1
fi

# Deploy to inactive stage
if ! deploy_to_inactive "$API_ID"; then
    exit 1
fi

# Wait for deployment
if ! wait_for_deployment "$API_ID" "$deployment_id"; then
    exit 1
fi

# Wait for approval
if ! wait_for_approval; then
    exit 1
fi

# Swap stages
if ! swap_stages "$API_ID"; then
    exit 1
fi

# Verify deployment
if ! verify_deployment "$API_ID"; then
    exit 1
fi

log "API Gateway Blue/Green deployment completed successfully" 