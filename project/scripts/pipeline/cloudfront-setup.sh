#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/cloudfront-setup.log"
APP_NAME="audit-system"
REGION="us-east-1"
BUCKET_BLUE="${APP_NAME}-blue"
BUCKET_GREEN="${APP_NAME}-green"
DISTRIBUTION_BLUE="${APP_NAME}-blue-dist"
DISTRIBUTION_GREEN="${APP_NAME}-green-dist"
KMS_KEY_ALIAS="${APP_NAME}-kms-key"
DOMAIN_NAME="audit-system.example.com"  # Replace with your domain
CERTIFICATE_ARN=""  # Replace with your ACM certificate ARN

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

# Create KMS key
create_kms_key() {
    log "Creating KMS key..."
    
    local key_id
    key_id=$(aws kms create-key \
        --description "KMS key for ${APP_NAME} S3 encryption" \
        --region "$REGION" \
        --query "KeyMetadata.KeyId" \
        --output text)
    
    if [ -z "$key_id" ]; then
        log "ERROR: Failed to create KMS key"
        return 1
    fi
    
    # Create alias for the key
    if ! aws kms create-alias \
        --alias-name "alias/$KMS_KEY_ALIAS" \
        --target-key-id "$key_id" \
        --region "$REGION"; then
        log "ERROR: Failed to create KMS key alias"
        return 1
    fi
    
    log "KMS key created with ID: $key_id"
    echo "$key_id"
    return 0
}

# Create S3 bucket
create_s3_bucket() {
    local bucket_name=$1
    local kms_key_id=$2
    log "Creating S3 bucket: $bucket_name"
    
    # Create bucket
    if ! aws s3api create-bucket \
        --bucket "$bucket_name" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"; then
        log "ERROR: Failed to create S3 bucket: $bucket_name"
        return 1
    fi
    
    # Enable versioning
    if ! aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled; then
        log "ERROR: Failed to enable versioning for bucket: $bucket_name"
        return 1
    fi
    
    # Configure server-side encryption
    if ! aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration "{
            \"Rules\": [
                {
                    \"ApplyServerSideEncryptionByDefault\": {
                        \"SSEAlgorithm\": \"aws:kms\",
                        \"KMSMasterKeyID\": \"$kms_key_id\"
                    }
                }
            ]
        }"; then
        log "ERROR: Failed to configure encryption for bucket: $bucket_name"
        return 1
    fi
    
    # Configure bucket policy for CloudFront
    if ! aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Sid\": \"AllowCloudFrontServicePrincipal\",
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"cloudfront.amazonaws.com\"
                    },
                    \"Action\": \"s3:GetObject\",
                    \"Resource\": \"arn:aws:s3:::$bucket_name/*\",
                    \"Condition\": {
                        \"StringEquals\": {
                            \"AWS:SourceArn\": \"arn:aws:cloudfront::$(aws sts get-caller-identity --query Account --output text):distribution/*\"
                        }
                    }
                }
            ]
        }"; then
        log "ERROR: Failed to configure bucket policy for: $bucket_name"
        return 1
    fi
    
    log "S3 bucket created successfully: $bucket_name"
    return 0
}

# Create CloudFront distribution
create_cloudfront_distribution() {
    local distribution_name=$1
    local bucket_name=$2
    log "Creating CloudFront distribution: $distribution_name"
    
    # Create origin access control
    local oac_id
    oac_id=$(aws cloudfront create-origin-access-control \
        --name "${distribution_name}-oac" \
        --origin-access-control-origin-type s3 \
        --signing-behavior always \
        --signing-protocol sigv4 \
        --region "$REGION" \
        --query "OriginAccessControl.Id" \
        --output text)
    
    if [ -z "$oac_id" ]; then
        log "ERROR: Failed to create origin access control"
        return 1
    fi
    
    # Create distribution
    local distribution_id
    distribution_id=$(aws cloudfront create-distribution \
        --origin-domain-name "${bucket_name}.s3.${REGION}.amazonaws.com" \
        --default-root-object index.html \
        --aliases "$DOMAIN_NAME" \
        --viewer-certificate "{
            \"ACMCertificateArn\": \"$CERTIFICATE_ARN\",
            \"SSLSupportMethod\": \"sni-only\",
            \"MinimumProtocolVersion\": \"TLSv1.2_2021\"
        }" \
        --default-cache-behavior "{
            \"TargetOriginId\": \"S3-${bucket_name}\",
            \"ViewerProtocolPolicy\": \"redirect-to-https\",
            \"AllowedMethods\": [\"GET\", \"HEAD\", \"OPTIONS\"],
            \"CachedMethods\": [\"GET\", \"HEAD\", \"OPTIONS\"],
            \"Compress\": true,
            \"ForwardedValues\": {
                \"QueryString\": false,
                \"Cookies\": {
                    \"Forward\": \"none\"
                }
            },
            \"MinTTL\": 0,
            \"DefaultTTL\": 86400,
            \"MaxTTL\": 31536000
        }" \
        --origins "[
            {
                \"Id\": \"S3-${bucket_name}\",
                \"DomainName\": \"${bucket_name}.s3.${REGION}.amazonaws.com\",
                \"S3OriginConfig\": {
                    \"OriginAccessIdentity\": \"\"
                },
                \"OriginAccessControlId\": \"${oac_id}\"
            }
        ]" \
        --enabled \
        --region "$REGION" \
        --query "Distribution.Id" \
        --output text)
    
    if [ -z "$distribution_id" ]; then
        log "ERROR: Failed to create CloudFront distribution"
        return 1
    fi
    
    log "CloudFront distribution created with ID: $distribution_id"
    echo "$distribution_id"
    return 0
}

# Main execution
log "Starting CloudFront Blue/Green setup..."

# Create KMS key
KMS_KEY_ID=$(create_kms_key)
if [ $? -ne 0 ]; then
    exit 1
fi

# Create S3 buckets
if ! create_s3_bucket "$BUCKET_BLUE" "$KMS_KEY_ID"; then
    exit 1
fi

if ! create_s3_bucket "$BUCKET_GREEN" "$KMS_KEY_ID"; then
    exit 1
fi

# Create CloudFront distributions
DIST_BLUE_ID=$(create_cloudfront_distribution "$DISTRIBUTION_BLUE" "$BUCKET_BLUE")
if [ $? -ne 0 ]; then
    exit 1
fi

DIST_GREEN_ID=$(create_cloudfront_distribution "$DISTRIBUTION_GREEN" "$BUCKET_GREEN")
if [ $? -ne 0 ]; then
    exit 1
fi

# Store distribution IDs in a file for future reference
echo "BLUE_DISTRIBUTION_ID=$DIST_BLUE_ID" > "../artifacts/cloudfront-ids.txt"
echo "GREEN_DISTRIBUTION_ID=$DIST_GREEN_ID" >> "../artifacts/cloudfront-ids.txt"

log "CloudFront Blue/Green setup completed successfully" 