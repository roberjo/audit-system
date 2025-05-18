#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/api-gateway-setup.log"
API_NAME="audit-system-api"
STAGE_BLUE="blue"
STAGE_GREEN="green"
LANE_BLUE="blue"
LANE_GREEN="green"
REGION="us-east-1"

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

# Check if API Gateway exists
check_api_exists() {
    log "Checking if API Gateway exists..."
    
    if aws apigateway get-rest-apis --region "$REGION" --query "items[?name=='$API_NAME']" --output text | grep -q "$API_NAME"; then
        log "API Gateway exists"
        return 0
    else
        log "API Gateway does not exist"
        return 1
    fi
}

# Create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    local api_id
    api_id=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --region "$REGION" \
        --query "id" \
        --output text)
    
    if [ -z "$api_id" ]; then
        log "ERROR: Failed to create API Gateway"
        return 1
    fi
    
    log "API Gateway created with ID: $api_id"
    echo "$api_id"
    return 0
}

# Create stages
create_stages() {
    local api_id=$1
    log "Creating stages..."
    
    # Create blue stage
    if ! aws apigateway create-stage \
        --rest-api-id "$api_id" \
        --stage-name "$STAGE_BLUE" \
        --region "$REGION" \
        --deployment-id "$(aws apigateway create-deployment --rest-api-id "$api_id" --stage-name "$STAGE_BLUE" --region "$REGION" --query "id" --output text)"; then
        log "ERROR: Failed to create blue stage"
        return 1
    fi
    
    # Create green stage
    if ! aws apigateway create-stage \
        --rest-api-id "$api_id" \
        --stage-name "$STAGE_GREEN" \
        --region "$REGION" \
        --deployment-id "$(aws apigateway create-deployment --rest-api-id "$api_id" --stage-name "$STAGE_GREEN" --region "$REGION" --query "id" --output text)"; then
        log "ERROR: Failed to create green stage"
        return 1
    fi
    
    log "Stages created successfully"
    return 0
}

# Create stage variables
create_stage_variables() {
    local api_id=$1
    log "Creating stage variables..."
    
    # Set blue stage variables
    if ! aws apigateway update-stage \
        --rest-api-id "$api_id" \
        --stage-name "$STAGE_BLUE" \
        --patch-operations op=replace,path=/variables/lane,value="$LANE_BLUE" \
        --region "$REGION"; then
        log "ERROR: Failed to set blue stage variables"
        return 1
    fi
    
    # Set green stage variables
    if ! aws apigateway update-stage \
        --rest-api-id "$api_id" \
        --stage-name "$STAGE_GREEN" \
        --patch-operations op=replace,path=/variables/lane,value="$LANE_GREEN" \
        --region "$REGION"; then
        log "ERROR: Failed to set green stage variables"
        return 1
    fi
    
    log "Stage variables created successfully"
    return 0
}

# Create custom domain
create_custom_domain() {
    local api_id=$1
    log "Creating custom domain..."
    
    # Create base path mapping for blue stage
    if ! aws apigateway create-base-path-mapping \
        --domain-name "$API_NAME.$REGION.amazonaws.com" \
        --rest-api-id "$api_id" \
        --stage "$STAGE_BLUE" \
        --base-path "$LANE_BLUE" \
        --region "$REGION"; then
        log "ERROR: Failed to create base path mapping for blue stage"
        return 1
    fi
    
    # Create base path mapping for green stage
    if ! aws apigateway create-base-path-mapping \
        --domain-name "$API_NAME.$REGION.amazonaws.com" \
        --rest-api-id "$api_id" \
        --stage "$STAGE_GREEN" \
        --base-path "$LANE_GREEN" \
        --region "$REGION"; then
        log "ERROR: Failed to create base path mapping for green stage"
        return 1
    fi
    
    log "Custom domain created successfully"
    return 0
}

# Main execution
log "Starting API Gateway setup..."

# Check if API Gateway exists
if ! check_api_exists; then
    # Create new API Gateway
    API_ID=$(create_api_gateway)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Create stages
    if ! create_stages "$API_ID"; then
        exit 1
    fi
    
    # Create stage variables
    if ! create_stage_variables "$API_ID"; then
        exit 1
    fi
    
    # Create custom domain
    if ! create_custom_domain "$API_ID"; then
        exit 1
    fi
else
    log "API Gateway already exists, skipping setup"
fi

log "API Gateway setup completed successfully" 