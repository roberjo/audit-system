#!/bin/bash

# Exit on error
set -e

# Configuration
DEPLOY_DIR="../artifacts/deploy"
LOG_FILE="../artifacts/deploy.log"
BACKUP_DIR="../artifacts/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred on line $1"
    log "Initiating rollback..."
    rollback
    exit 1
}

trap 'handle_error $LINENO' ERR

# Rollback function
rollback() {
    if [ -d "$BACKUP_DIR/last_deployment" ]; then
        log "Rolling back to previous deployment..."
        rm -rf "$DEPLOY_DIR/current"
        cp -r "$BACKUP_DIR/last_deployment" "$DEPLOY_DIR/current"
        log "Rollback completed"
    else
        log "No backup found for rollback"
    fi
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if application is running
    if ! curl -s http://localhost:3000/health > /dev/null; then
        log "ERROR: Application health check failed"
        return 1
    fi
    
    # Add more validation steps as needed
    return 0
}

# Start deployment process
log "Starting deployment process..."

# Create necessary directories
mkdir -p "$DEPLOY_DIR" "$BACKUP_DIR"

# Backup current deployment if exists
if [ -d "$DEPLOY_DIR/current" ]; then
    log "Backing up current deployment..."
    cp -r "$DEPLOY_DIR/current" "$BACKUP_DIR/last_deployment"
fi

# Deploy new version
log "Deploying new version..."
cp -r "../artifacts/build/build_$TIMESTAMP.tar.gz" "$DEPLOY_DIR/current"

# Extract deployment
log "Extracting deployment..."
tar -xzf "$DEPLOY_DIR/current/build_$TIMESTAMP.tar.gz" -C "$DEPLOY_DIR/current"

# Validate deployment
if ! validate_deployment; then
    log "Deployment validation failed"
    rollback
    exit 1
fi

# Cleanup old backups (keep last 5)
log "Cleaning up old backups..."
ls -t "$BACKUP_DIR" | tail -n +6 | xargs -I {} rm -rf "$BACKUP_DIR/{}"

# Print deployment summary
log "Deployment Summary:"
log "Deployment Directory: $DEPLOY_DIR"
log "Backup Directory: $BACKUP_DIR"
log "Deployment completed at: $(date)" 