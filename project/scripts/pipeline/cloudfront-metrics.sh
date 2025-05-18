#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/cloudfront-metrics.log"
METRICS_DIR="../artifacts/metrics"
APP_NAME="audit-system"
REGION="us-east-1"
BUCKET_BLUE="${APP_NAME}-blue"
BUCKET_GREEN="${APP_NAME}-green"
DISTRIBUTION_BLUE="${APP_NAME}-blue-dist"
DISTRIBUTION_GREEN="${APP_NAME}-green-dist"
METRICS_INTERVAL=300  # 5 minutes
RETENTION_DAYS=30

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

# Create metrics directory
create_metrics_dir() {
    log "Creating metrics directory..."
    
    if [ ! -d "$METRICS_DIR" ]; then
        mkdir -p "$METRICS_DIR"
    fi
    
    # Create subdirectories for different metric types
    mkdir -p "$METRICS_DIR/cloudfront"
    mkdir -p "$METRICS_DIR/s3"
    mkdir -p "$METRICS_DIR/analysis"
}

# Collect CloudFront metrics
collect_cloudfront_metrics() {
    local dist_id=$1
    local dist_name=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local metrics_file="$METRICS_DIR/cloudfront/${dist_name}_${timestamp}.json"
    
    log "Collecting CloudFront metrics for $dist_name..."
    
    # Collect various CloudFront metrics
    aws cloudfront get-metric-statistics \
        --namespace AWS/CloudFront \
        --metric-names BytesDownloaded BytesUploaded Requests TotalErrorRate CacheHitRate \
        --dimensions Name=DistributionId,Value="$dist_id" Name=Region,Value=Global \
        --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 300 \
        --statistics Average Sum \
        --region "$REGION" > "$metrics_file"
    
    log "CloudFront metrics saved to $metrics_file"
}

# Collect S3 metrics
collect_s3_metrics() {
    local bucket_name=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local metrics_file="$METRICS_DIR/s3/${bucket_name}_${timestamp}.json"
    
    log "Collecting S3 metrics for $bucket_name..."
    
    # Collect various S3 metrics
    aws cloudwatch get-metric-statistics \
        --namespace AWS/S3 \
        --metric-names BucketSizeBytes NumberOfObjects AllRequests GetRequests PutRequests \
        --dimensions Name=BucketName,Value="$bucket_name" Name=StorageType,Value=StandardStorage \
        --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 300 \
        --statistics Average Sum \
        --region "$REGION" > "$metrics_file"
    
    log "S3 metrics saved to $metrics_file"
}

# Analyze metrics
analyze_metrics() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local analysis_file="$METRICS_DIR/analysis/analysis_${timestamp}.json"
    
    log "Analyzing metrics..."
    
    # Initialize analysis JSON
    echo "{
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"cloudfront\": {
            \"blue\": {},
            \"green\": {}
        },
        \"s3\": {
            \"blue\": {},
            \"green\": {}
        },
        \"recommendations\": []
    }" > "$analysis_file"
    
    # Analyze CloudFront metrics
    for dist in "blue" "green"; do
        local dist_id
        if [ "$dist" = "blue" ]; then
            dist_id=$BLUE_DISTRIBUTION_ID
        else
            dist_id=$GREEN_DISTRIBUTION_ID
        fi
        
        # Get latest metrics file
        local latest_metrics
        latest_metrics=$(ls -t "$METRICS_DIR/cloudfront/${APP_NAME}-${dist}-dist_"*.json | head -n1)
        
        if [ -n "$latest_metrics" ]; then
            # Extract key metrics
            local error_rate
            local hit_rate
            local requests
            
            error_rate=$(jq -r '.Datapoints[] | select(.MetricName=="TotalErrorRate") | .Average' "$latest_metrics")
            hit_rate=$(jq -r '.Datapoints[] | select(.MetricName=="CacheHitRate") | .Average' "$latest_metrics")
            requests=$(jq -r '.Datapoints[] | select(.MetricName=="Requests") | .Sum' "$latest_metrics")
            
            # Update analysis
            jq --arg dist "$dist" \
               --arg error_rate "$error_rate" \
               --arg hit_rate "$hit_rate" \
               --arg requests "$requests" \
               '.cloudfront[$dist] = {
                   "error_rate": $error_rate,
                   "hit_rate": $hit_rate,
                   "requests": $requests
               }' "$analysis_file" > "${analysis_file}.tmp"
            mv "${analysis_file}.tmp" "$analysis_file"
            
            # Add recommendations
            if (( $(echo "$error_rate > 0.01" | bc -l) )); then
                jq --arg dist "$dist" \
                   '.recommendations += ["High error rate detected in " + $dist + " distribution. Consider investigating."]' \
                   "$analysis_file" > "${analysis_file}.tmp"
                mv "${analysis_file}.tmp" "$analysis_file"
            fi
            
            if (( $(echo "$hit_rate < 0.8" | bc -l) )); then
                jq --arg dist "$dist" \
                   '.recommendations += ["Low cache hit rate in " + $dist + " distribution. Consider adjusting cache settings."]' \
                   "$analysis_file" > "${analysis_file}.tmp"
                mv "${analysis_file}.tmp" "$analysis_file"
            fi
        fi
    done
    
    # Analyze S3 metrics
    for bucket in "blue" "green"; do
        local bucket_name="${APP_NAME}-${bucket}"
        
        # Get latest metrics file
        local latest_metrics
        latest_metrics=$(ls -t "$METRICS_DIR/s3/${bucket_name}_"*.json | head -n1)
        
        if [ -n "$latest_metrics" ]; then
            # Extract key metrics
            local size
            local objects
            local requests
            
            size=$(jq -r '.Datapoints[] | select(.MetricName=="BucketSizeBytes") | .Average' "$latest_metrics")
            objects=$(jq -r '.Datapoints[] | select(.MetricName=="NumberOfObjects") | .Average' "$latest_metrics")
            requests=$(jq -r '.Datapoints[] | select(.MetricName=="AllRequests") | .Sum' "$latest_metrics")
            
            # Update analysis
            jq --arg bucket "$bucket" \
               --arg size "$size" \
               --arg objects "$objects" \
               --arg requests "$requests" \
               '.s3[$bucket] = {
                   "size_bytes": $size,
                   "object_count": $objects,
                   "request_count": $requests
               }' "$analysis_file" > "${analysis_file}.tmp"
            mv "${analysis_file}.tmp" "$analysis_file"
            
            # Add recommendations
            if (( $(echo "$size > 1073741824" | bc -l) )); then  # 1GB
                jq --arg bucket "$bucket" \
                   '.recommendations += ["Large bucket size detected in " + $bucket + " bucket. Consider cleanup."]' \
                   "$analysis_file" > "${analysis_file}.tmp"
                mv "${analysis_file}.tmp" "$analysis_file"
            fi
        fi
    done
    
    log "Analysis saved to $analysis_file"
}

# Cleanup old metrics
cleanup_old_metrics() {
    log "Cleaning up old metrics..."
    
    find "$METRICS_DIR" -type f -mtime +$RETENTION_DAYS -delete
}

# Main metrics collection loop
collect_metrics() {
    log "Starting metrics collection..."
    
    while true; do
        # Collect CloudFront metrics
        collect_cloudfront_metrics "$BLUE_DISTRIBUTION_ID" "$DISTRIBUTION_BLUE"
        collect_cloudfront_metrics "$GREEN_DISTRIBUTION_ID" "$DISTRIBUTION_GREEN"
        
        # Collect S3 metrics
        collect_s3_metrics "$BUCKET_BLUE"
        collect_s3_metrics "$BUCKET_GREEN"
        
        # Analyze metrics
        analyze_metrics
        
        # Cleanup old metrics
        cleanup_old_metrics
        
        sleep "$METRICS_INTERVAL"
    done
}

# Main execution
log "Starting CloudFront metrics collection..."

# Get distribution IDs
if ! get_distribution_ids; then
    exit 1
fi

# Create metrics directory
create_metrics_dir

# Start metrics collection
collect_metrics 