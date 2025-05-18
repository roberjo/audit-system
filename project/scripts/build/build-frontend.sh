#!/bin/bash

# Build Frontend Application Script
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Navigate to frontend directory
FRONTEND_PATH="src/frontend"
if [ ! -d "$FRONTEND_PATH" ]; then
    log "Error: Frontend directory not found: $FRONTEND_PATH"
    exit 1
fi

cd "$FRONTEND_PATH"

# Install dependencies
log "Installing dependencies..."
npm install
if [ $? -ne 0 ]; then
    log "Error: Failed to install dependencies"
    exit 1
fi

# Run linting
log "Running linting..."
npm run lint
if [ $? -ne 0 ]; then
    log "Error: Linting failed"
    exit 1
fi

# Run tests
log "Running tests..."
npm test
if [ $? -ne 0 ]; then
    log "Error: Tests failed"
    exit 1
fi

# Build application
log "Building application..."
npm run build
if [ $? -ne 0 ]; then
    log "Error: Build failed"
    exit 1
fi

log "Frontend build completed successfully"

# Return to original directory
cd - > /dev/null 