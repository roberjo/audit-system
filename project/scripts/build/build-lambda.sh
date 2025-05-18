#!/bin/bash

# Build Lambda Function Script
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if function name is provided
if [ -z "$1" ]; then
    log "Error: Function name is required"
    echo "Usage: $0 <function-name>"
    exit 1
fi

FUNCTION_NAME=$1
LAMBDA_PATH="src/lambda/$FUNCTION_NAME"

# Check if Lambda function directory exists
if [ ! -d "$LAMBDA_PATH" ]; then
    log "Error: Lambda function directory not found: $LAMBDA_PATH"
    exit 1
fi

# Navigate to Lambda function directory
cd "$LAMBDA_PATH"

# Install dependencies
log "Installing dependencies..."
npm install
if [ $? -ne 0 ]; then
    log "Error: Failed to install dependencies"
    exit 1
fi

# Build TypeScript code
log "Building TypeScript code..."
npm run build
if [ $? -ne 0 ]; then
    log "Error: Failed to build TypeScript code"
    exit 1
fi

# Create deployment package
log "Creating deployment package..."
DIST_PATH="dist"
if [ ! -d "$DIST_PATH" ]; then
    log "Error: Build output directory not found: $DIST_PATH"
    exit 1
fi

# Create deployment package
ZIP_PATH="$DIST_PATH/$FUNCTION_NAME.zip"
if [ -f "$ZIP_PATH" ]; then
    rm "$ZIP_PATH"
fi

# Add node_modules and dist contents to the zip
cd "$DIST_PATH"
zip -r "$FUNCTION_NAME.zip" ./*
cd ..
zip -r "$DIST_PATH/$FUNCTION_NAME.zip" node_modules

log "Build completed successfully. Deployment package created at: $ZIP_PATH"

# Return to original directory
cd - > /dev/null 