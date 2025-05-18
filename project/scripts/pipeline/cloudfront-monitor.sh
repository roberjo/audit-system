#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/cloudfront-monitor.log"
APP_NAME="audit-system"
REGION="us-east-1"
BUCKET_BLUE="${APP_NAME}-blue"
BUCKET_GREEN="${APP_NAME}-green"
DISTRIBUTION_BLUE="${APP_NAME}-blue-dist"
DISTRIBUTION_GREEN="${APP_NAME}-green-dist"
MONITOR_INTERVAL=60  # 60 seconds
ERROR_THRESHOLD=5  # Number of errors before alerting
ALERT_EMAIL="admin@example.com"  # Replace with your email

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

# Get distribution IDs
get_distribution_ids() {
    log "Getting distribution IDs..."
    
    if [ ! -f "../artifacts/cloudfront-ids.txt" ]; then
        log "ERROR: Distribution IDs file not found"
        return 1
    fi
    
    source "../artifacts/cloudfront-ids.txt"
    
    if [ -z "$BLUE_DISTRIBUTION_ID" ] || [ -z "$GREEN_DISTRIBUTION_ID" ]; then
        log "ERROR: Distribution IDs not found in file"
        return 1
    fi
    
    return 0
}

# Check CloudFront distribution health
check_distribution_health() {
    local dist_id=$1
    local dist_name=$2
    log "Checking health of distribution: $dist_name"
    
    # Get distribution status
    local status
    status=$(aws cloudfront get-distribution \
        --id "$dist_id" \
        --region "$REGION" \
        --query "Distribution.Status" \
        --output text)
    
    if [ "$status" != "Deployed" ]; then
        log "WARNING: Distribution $dist_name is not deployed (Status: $status)"
        return 1
    fi
    
    # Get error rate
    local error_rate
    error_rate=$(aws cloudfront get-metric-statistics \
        --namespace AWS/CloudFront \
        --metric-name 5xxErrorRate \
        --dimensions Name=DistributionId,Value="$dist_id" Name=Region,Value=Global \
        --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 300 \
        --statistics Average \
        --region "$REGION" \
        --query "Datapoints[0].Average" \
        --output text)
    
    if (( $(echo "$error_rate > 0.01" | bc -l) )); then
        log "WARNING: High error rate for distribution $dist_name: $error_rate"
        return 1
    fi
    
    log "Distribution $dist_name is healthy"
    return 0
}

# Check S3 bucket health
check_bucket_health() {
    local bucket_name=$1
    log "Checking health of bucket: $bucket_name"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "ERROR: Bucket $bucket_name does not exist"
        return 1
    fi
    
    # Check bucket versioning
    local versioning
    versioning=$(aws s3api get-bucket-versioning \
        --bucket "$bucket_name" \
        --query "Status" \
        --output text)
    
    if [ "$versioning" != "Enabled" ]; then
        log "WARNING: Versioning is not enabled for bucket $bucket_name"
        return 1
    fi
    
    # Check bucket encryption
    local encryption
    encryption=$(aws s3api get-bucket-encryption \
        --bucket "$bucket_name" \
        --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" \
        --output text)
    
    if [ "$encryption" != "aws:kms" ]; then
        log "WARNING: KMS encryption is not enabled for bucket $bucket_name"
        return 1
    fi
    
    # Check if index.html exists
    if ! aws s3 ls "s3://$bucket_name/index.html" > /dev/null 2>&1; then
        log "WARNING: index.html not found in bucket $bucket_name"
        return 1
    fi
    
    log "Bucket $bucket_name is healthy"
    return 0
}

# Check CloudFront cache hit rate
check_cache_hit_rate() {
    local dist_id=$1
    local dist_name=$2
    log "Checking cache hit rate for distribution: $dist_name"
    
    local hit_rate
    hit_rate=$(aws cloudfront get-metric-statistics \
        --namespace AWS/CloudFront \
        --metric-name CacheHitRate \
        --dimensions Name=DistributionId,Value="$dist_id" Name=Region,Value=Global \
        --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 300 \
        --statistics Average \
        --region "$REGION" \
        --query "Datapoints[0].Average" \
        --output text)
    
    if (( $(echo "$hit_rate < 0.8" | bc -l) )); then
        log "WARNING: Low cache hit rate for distribution $dist_name: $hit_rate"
        return 1
    fi
    
    log "Cache hit rate for distribution $dist_name is good: $hit_rate"
    return 0
}

# Check CloudFront latency
check_latency() {
    local dist_id=$1
    local dist_name=$2
    log "Checking latency for distribution: $dist_name"
    
    local latency
    latency=$(aws cloudfront get-metric-statistics \
        --namespace AWS/CloudFront \
        --metric-name TotalErrorRate \
        --dimensions Name=DistributionId,Value="$dist_id" Name=Region,Value=Global \
        --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 300 \
        --statistics Average \
        --region "$REGION" \
        --query "Datapoints[0].Average" \
        --output text)
    
    if (( $(echo "$latency > 0.1" | bc -l) )); then
        log "WARNING: High latency for distribution $dist_name: $latency"
        return 1
    fi
    
    log "Latency for distribution $dist_name is good: $latency"
    return 0
}

# Send alert
send_alert() {
    local subject=$1
    local message=$2
    log "Sending alert: $subject"
    
    # Send email alert
    aws ses send-email \
        --from "$ALERT_EMAIL" \
        --destination "ToAddresses=$ALERT_EMAIL" \
        --message "Subject={Data=$subject,Charset=UTF-8},Body={Text={Data=$message,Charset=UTF-8}" \
        --region "$REGION"
}

# Main monitoring loop
monitor() {
    log "Starting monitoring..."
    
    local error_count=0
    
    while true; do
        local has_errors=false
        
        # Check blue distribution
        if ! check_distribution_health "$BLUE_DISTRIBUTION_ID" "$DISTRIBUTION_BLUE"; then
            has_errors=true
        fi
        
        # Check green distribution
        if ! check_distribution_health "$GREEN_DISTRIBUTION_ID" "$DISTRIBUTION_GREEN"; then
            has_errors=true
        fi
        
        # Check blue bucket
        if ! check_bucket_health "$BUCKET_BLUE"; then
            has_errors=true
        fi
        
        # Check green bucket
        if ! check_bucket_health "$BUCKET_GREEN"; then
            has_errors=true
        fi
        
        # Check cache hit rates
        if ! check_cache_hit_rate "$BLUE_DISTRIBUTION_ID" "$DISTRIBUTION_BLUE"; then
            has_errors=true
        fi
        
        if ! check_cache_hit_rate "$GREEN_DISTRIBUTION_ID" "$DISTRIBUTION_GREEN"; then
            has_errors=true
        fi
        
        # Check latencies
        if ! check_latency "$BLUE_DISTRIBUTION_ID" "$DISTRIBUTION_BLUE"; then
            has_errors=true
        fi
        
        if ! check_latency "$GREEN_DISTRIBUTION_ID" "$DISTRIBUTION_GREEN"; then
            has_errors=true
        fi
        
        # Handle errors
        if [ "$has_errors" = true ]; then
            error_count=$((error_count + 1))
            if [ $error_count -ge $ERROR_THRESHOLD ]; then
                send_alert "CloudFront Monitoring Alert" "Multiple errors detected in CloudFront setup. Check logs for details."
                error_count=0
            fi
        else
            error_count=0
        fi
        
        sleep "$MONITOR_INTERVAL"
    done
}

# Main execution
log "Starting CloudFront monitoring..."

# Get distribution IDs
if ! get_distribution_ids; then
    exit 1
fi

# Start monitoring
monitor 