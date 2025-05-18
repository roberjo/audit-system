#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/docker.log"
DOCKERFILE_PATH="../Dockerfile"
IMAGE_NAME="audit-system"
REGISTRY="$DOCKER_REGISTRY"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
GIT_SHA=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

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

# Build Docker image
build_image() {
    local tag=$1
    log "Building Docker image with tag: $tag"
    
    if ! docker build \
        --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
        --build-arg VCS_REF="$GIT_SHA" \
        --build-arg VERSION="$tag" \
        -t "$REGISTRY/$IMAGE_NAME:$tag" \
        -f "$DOCKERFILE_PATH" \
        ..; then
        log "ERROR: Docker build failed"
        return 1
    fi
    
    log "Docker image built successfully"
    return 0
}

# Push Docker image
push_image() {
    local tag=$1
    log "Pushing Docker image with tag: $tag"
    
    if ! docker push "$REGISTRY/$IMAGE_NAME:$tag"; then
        log "ERROR: Docker push failed"
        return 1
    fi
    
    log "Docker image pushed successfully"
    return 0
}

# Tag Docker image
tag_image() {
    local source_tag=$1
    local target_tag=$2
    log "Tagging Docker image from $source_tag to $target_tag"
    
    if ! docker tag "$REGISTRY/$IMAGE_NAME:$source_tag" "$REGISTRY/$IMAGE_NAME:$target_tag"; then
        log "ERROR: Docker tag failed"
        return 1
    fi
    
    log "Docker image tagged successfully"
    return 0
}

# Main execution
log "Starting Docker build and push process..."

# Build with timestamp tag
if ! build_image "$TIMESTAMP"; then
    exit 1
fi

# Build with git SHA tag
if ! build_image "$GIT_SHA"; then
    exit 1
fi

# Tag based on branch
if [ "$GIT_BRANCH" = "main" ]; then
    if ! tag_image "$GIT_SHA" "latest"; then
        exit 1
    fi
    if ! tag_image "$GIT_SHA" "stable"; then
        exit 1
    fi
elif [ "$GIT_BRANCH" = "develop" ]; then
    if ! tag_image "$GIT_SHA" "dev"; then
        exit 1
    fi
fi

# Push all tags
for tag in "$TIMESTAMP" "$GIT_SHA"; do
    if ! push_image "$tag"; then
        exit 1
    fi
done

# Push branch-specific tags
if [ "$GIT_BRANCH" = "main" ]; then
    for tag in "latest" "stable"; do
        if ! push_image "$tag"; then
            exit 1
        fi
    done
elif [ "$GIT_BRANCH" = "develop" ]; then
    if ! push_image "dev"; then
        exit 1
    fi
fi

# Cleanup local images
log "Cleaning up local images..."
docker image prune -f

log "Docker build and push process completed successfully" 