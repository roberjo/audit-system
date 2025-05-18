#!/bin/bash

# Exit on error
set -e

# Configuration
BUILD_DIR="../artifacts/build"
LOG_FILE="../artifacts/build.log"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

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

# Start build process
log "Starting build process..."

# Clean previous build artifacts
log "Cleaning previous build artifacts..."
rm -rf "$BUILD_DIR"/*

# Install dependencies
log "Installing dependencies..."
npm install

# Run tests
log "Running tests..."
npm test

# Build the project
log "Building project..."
npm run build

# Create build artifact
log "Creating build artifact..."
tar -czf "$BUILD_DIR/build_$TIMESTAMP.tar.gz" -C dist .

# Verify build
if [ -f "$BUILD_DIR/build_$TIMESTAMP.tar.gz" ]; then
    log "Build completed successfully"
    log "Build artifact: $BUILD_DIR/build_$TIMESTAMP.tar.gz"
else
    log "ERROR: Build artifact not found"
    exit 1
fi

# Print build summary
log "Build Summary:"
log "Build Directory: $BUILD_DIR"
log "Build Artifact: build_$TIMESTAMP.tar.gz"
log "Build completed at: $(date)" 