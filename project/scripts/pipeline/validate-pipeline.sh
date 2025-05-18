#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/pipeline.log"
REQUIRED_TOOLS=("docker" "kubectl" "aws" "terraform")
REQUIRED_ENV_VARS=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "KUBE_CONFIG" "DOCKER_REGISTRY")
MIN_DISK_SPACE=10  # GB
MIN_MEMORY=4      # GB

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

# Check required tools
check_required_tools() {
    log "Checking required tools..."
    local missing_tools=()
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR: Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    log "All required tools are installed"
    return 0
}

# Check environment variables
check_env_vars() {
    log "Checking environment variables..."
    local missing_vars=()
    
    for var in "${REQUIRED_ENV_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log "ERROR: Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    log "All required environment variables are set"
    return 0
}

# Check system resources
check_system_resources() {
    log "Checking system resources..."
    
    # Check disk space
    local available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt "$MIN_DISK_SPACE" ]; then
        log "ERROR: Insufficient disk space. Required: ${MIN_DISK_SPACE}GB, Available: ${available_space}GB"
        return 1
    fi
    
    # Check memory
    local available_memory=$(free -g | awk '/Mem:/ {print $7}')
    if [ "$available_memory" -lt "$MIN_MEMORY" ]; then
        log "ERROR: Insufficient memory. Required: ${MIN_MEMORY}GB, Available: ${available_memory}GB"
        return 1
    fi
    
    log "System resources are sufficient"
    return 0
}

# Check Docker registry access
check_docker_registry() {
    log "Checking Docker registry access..."
    if ! docker login "$DOCKER_REGISTRY" -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD" &> /dev/null; then
        log "ERROR: Failed to access Docker registry"
        return 1
    fi
    
    log "Docker registry access verified"
    return 0
}

# Check Kubernetes cluster access
check_kubernetes_access() {
    log "Checking Kubernetes cluster access..."
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR: Failed to access Kubernetes cluster"
        return 1
    fi
    
    log "Kubernetes cluster access verified"
    return 0
}

# Check AWS credentials
check_aws_credentials() {
    log "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR: Invalid AWS credentials"
        return 1
    fi
    
    log "AWS credentials verified"
    return 0
}

# Main validation
log "Starting pipeline validation..."

# Run all checks
if ! check_required_tools; then
    exit 1
fi

if ! check_env_vars; then
    exit 1
fi

if ! check_system_resources; then
    exit 1
fi

if ! check_docker_registry; then
    exit 1
fi

if ! check_kubernetes_access; then
    exit 1
fi

if ! check_aws_credentials; then
    exit 1
fi

log "Pipeline validation completed successfully" 