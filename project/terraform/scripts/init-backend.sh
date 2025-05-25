#!/bin/bash

# Check if environment parameter is provided
if [ -z "$1" ]; then
    echo "Error: Environment parameter is required"
    echo "Usage: $0 <environment>"
    exit 1
fi

ENVIRONMENT=$1

# AWS Region
REGION="us-east-1"

# S3 bucket name for Terraform state
BUCKET_NAME="audit-system-terraform-state"

# DynamoDB table name for state locking
TABLE_NAME="audit-system-terraform-locks"

# Create S3 bucket if it doesn't exist
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "Creating S3 bucket for Terraform state..."
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled

    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
fi

# Create DynamoDB table if it doesn't exist
if ! aws dynamodb describe-table --table-name "$TABLE_NAME" 2>/dev/null; then
    echo "Creating DynamoDB table for state locking..."
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
fi

# Initialize Terraform
echo "Initializing Terraform for $ENVIRONMENT environment..."
cd "../environments/$ENVIRONMENT"
terraform init

echo "Backend initialization complete!" 