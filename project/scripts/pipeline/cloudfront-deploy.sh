#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/cloudfront-deploy.log"
APP_NAME="audit-system"
REGION="us-east-1"
BUCKET_BLUE="${APP_NAME}-blue"
BUCKET_GREEN="${APP_NAME}-green"
DISTRIBUTION_BLUE="${APP_NAME}-blue-dist"
DISTRIBUTION_GREEN="${APP_NAME}-green-dist"
BUILD_DIR="../build"  # React build output directory
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

# Get distribution IDs
get_distribution_ids() {
    log "Getting distribution IDs..."
    
    if [ ! -f "../artifacts/cloudfront-ids.txt" ]; then
        log "ERROR: Distribution IDs file not found"
        return 1
    fi
    
    source "../artifacts/cloudfront-ids.txt"
    
    if [ -z "$BLUE_DISTRIBUTION_ID" ] || [ -z "$GREEN_DISTRIBUTION_ID" ]; then
        log "ERROR: Distribution IDs not found in file"
        return 1
    fi
    
    return 0
}

# Determine active and inactive distributions
determine_distributions() {
    log "Determining active and inactive distributions..."
    
    # Get distribution statuses
    local blue_status
    local green_status
    
    blue_status=$(aws cloudfront get-distribution \
        --id "$BLUE_DISTRIBUTION_ID" \
        --region "$REGION" \
        --query "Distribution.Status" \
        --output text)
    
    green_status=$(aws cloudfront get-distribution \
        --id "$GREEN_DISTRIBUTION_ID" \
        --region "$REGION" \
        --query "Distribution.Status" \
        --output text)
    
    # Check which distribution is enabled
    local blue_enabled
    local green_enabled
    
    blue_enabled=$(aws cloudfront get-distribution \
        --id "$BLUE_DISTRIBUTION_ID" \
        --region "$REGION" \
        --query "Distribution.DistributionConfig.Enabled" \
        --output text)
    
    green_enabled=$(aws cloudfront get-distribution \
        --id "$GREEN_DISTRIBUTION_ID" \
        --region "$REGION" \
        --query "Distribution.DistributionConfig.Enabled" \
        --output text)
    
    if [ "$blue_enabled" = "True" ]; then
        ACTIVE_DIST_ID=$BLUE_DISTRIBUTION_ID
        INACTIVE_DIST_ID=$GREEN_DISTRIBUTION_ID
        ACTIVE_BUCKET=$BUCKET_BLUE
        INACTIVE_BUCKET=$BUCKET_GREEN
    elif [ "$green_enabled" = "True" ]; then
        ACTIVE_DIST_ID=$GREEN_DISTRIBUTION_ID
        INACTIVE_DIST_ID=$BLUE_DISTRIBUTION_ID
        ACTIVE_BUCKET=$BUCKET_GREEN
        INACTIVE_BUCKET=$BUCKET_BLUE
    else
        log "ERROR: No active distribution found"
        return 1
    fi
    
    log "Active distribution: $ACTIVE_DIST_ID"
    log "Inactive distribution: $INACTIVE_DIST_ID"
    return 0
}

# Deploy to inactive bucket
deploy_to_inactive() {
    log "Deploying to inactive bucket: $INACTIVE_BUCKET"
    
    # Check if build directory exists
    if [ ! -d "$BUILD_DIR" ]; then
        log "ERROR: Build directory not found: $BUILD_DIR"
        return 1
    fi
    
    # Upload files to S3
    if ! aws s3 sync "$BUILD_DIR" "s3://$INACTIVE_BUCKET/" \
        --delete \
        --cache-control "public, max-age=31536000" \
        --exclude "*.html" \
        --exclude "*.json"; then
        log "ERROR: Failed to upload static assets"
        return 1
    fi
    
    # Upload HTML and JSON files with no caching
    if ! aws s3 sync "$BUILD_DIR" "s3://$INACTIVE_BUCKET/" \
        --delete \
        --cache-control "no-cache" \
        --include "*.html" \
        --include "*.json"; then
        log "ERROR: Failed to upload HTML and JSON files"
        return 1
    fi
    
    log "Deployment to inactive bucket completed"
    return 0
}

# Wait for deployment
wait_for_deployment() {
    log "Waiting for deployment to complete..."
    
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        # Check if files are accessible
        if aws s3 ls "s3://$INACTIVE_BUCKET/index.html" > /dev/null 2>&1; then
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

# Swap distributions
swap_distributions() {
    log "Swapping distributions..."
    
    # Get current distribution configs
    local active_config
    local inactive_config
    
    active_config=$(aws cloudfront get-distribution-config \
        --id "$ACTIVE_DIST_ID" \
        --region "$REGION")
    
    inactive_config=$(aws cloudfront get-distribution-config \
        --id "$INACTIVE_DIST_ID" \
        --region "$REGION")
    
    # Disable active distribution
    if ! aws cloudfront update-distribution \
        --id "$ACTIVE_DIST_ID" \
        --distribution-config "$(echo "$active_config" | jq '.DistributionConfig.Enabled = false')" \
        --if-match "$(echo "$active_config" | jq -r '.ETag')" \
        --region "$REGION"; then
        log "ERROR: Failed to disable active distribution"
        return 1
    fi
    
    # Enable inactive distribution
    if ! aws cloudfront update-distribution \
        --id "$INACTIVE_DIST_ID" \
        --distribution-config "$(echo "$inactive_config" | jq '.DistributionConfig.Enabled = true')" \
        --if-match "$(echo "$inactive_config" | jq -r '.ETag')" \
        --region "$REGION"; then
        log "ERROR: Failed to enable inactive distribution"
        return 1
    fi
    
    log "Distributions swapped successfully"
    return 0
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check if new active distribution is enabled
    local new_active_enabled
    new_active_enabled=$(aws cloudfront get-distribution \
        --id "$INACTIVE_DIST_ID" \
        --region "$REGION" \
        --query "Distribution.DistributionConfig.Enabled" \
        --output text)
    
    if [ "$new_active_enabled" != "True" ]; then
        log "ERROR: New active distribution not properly enabled"
        return 1
    fi
    
    # Check if old active distribution is disabled
    local old_active_enabled
    old_active_enabled=$(aws cloudfront get-distribution \
        --id "$ACTIVE_DIST_ID" \
        --region "$REGION" \
        --query "Distribution.DistributionConfig.Enabled" \
        --output text)
    
    if [ "$old_active_enabled" != "False" ]; then
        log "ERROR: Old active distribution not properly disabled"
        return 1
    fi
    
    log "Deployment verified successfully"
    return 0
}

# Main execution
log "Starting CloudFront Blue/Green deployment..."

# Get distribution IDs
if ! get_distribution_ids; then
    exit 1
fi

# Determine active and inactive distributions
if ! determine_distributions; then
    exit 1
fi

# Deploy to inactive bucket
if ! deploy_to_inactive; then
    exit 1
fi

# Wait for deployment
if ! wait_for_deployment; then
    exit 1
fi

# Wait for approval
if ! wait_for_approval; then
    exit 1
fi

# Swap distributions
if ! swap_distributions; then
    exit 1
fi

# Verify deployment
if ! verify_deployment; then
    exit 1
fi

log "CloudFront Blue/Green deployment completed successfully" 