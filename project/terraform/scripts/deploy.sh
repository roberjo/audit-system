#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <environment> [--plan]"
    echo "  environment: dev, staging, or prod"
    echo "  --plan: Generate plan only without applying"
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

# Check for plan flag
PLAN_ONLY=false
if [ "$2" == "--plan" ]; then
    PLAN_ONLY=true
fi

# Set working directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Initialize backend if needed
if [ ! -d "../environments/$ENVIRONMENT/.terraform" ]; then
    echo "Initializing backend for $ENVIRONMENT environment..."
    ./init-backend.sh "$ENVIRONMENT"
fi

# Set environment variables
export TF_WORKSPACE="$ENVIRONMENT"

# Change to environment directory
cd "../environments/$ENVIRONMENT"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Format and validate
echo "Formatting and validating Terraform configuration..."
terraform fmt
terraform validate

if [ "$PLAN_ONLY" = true ]; then
    # Generate and show plan
    echo "Generating Terraform plan..."
    terraform plan -out=tfplan
else
    # Apply changes
    echo "Applying Terraform configuration..."
    terraform apply -auto-approve

    # Output important information
    echo -e "\nDeployment Summary:"
    echo "------------------"
    terraform output
fi

echo -e "\nDeployment process completed!" 