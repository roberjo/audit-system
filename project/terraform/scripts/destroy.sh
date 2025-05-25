#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <environment> [--force]"
    echo "  environment: dev, staging, or prod"
    echo "  --force: Skip confirmation prompt"
    exit 1
}

# Check if environment parameter is provided
if [ -z "$1" ]; then
    usage
fi

# Validate environment
ENVIRONMENT=$1
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "Error: Invalid environment. Must be dev, staging, or prod"
    usage
fi

# Check for force flag
FORCE=false
if [ "$2" == "--force" ]; then
    FORCE=true
fi

# Set working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Change to environment directory
cd "../environments/$ENVIRONMENT"

# Confirm destruction
if [ "$FORCE" = false ]; then
    read -p "Are you sure you want to destroy all resources in the $ENVIRONMENT environment? This action cannot be undone. (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 1
    fi
fi

# Set environment variables
export TF_WORKSPACE="$ENVIRONMENT"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Destroy resources
echo "Destroying resources in $ENVIRONMENT environment..."
terraform destroy -auto-approve

echo -e "\nCleanup completed!" 