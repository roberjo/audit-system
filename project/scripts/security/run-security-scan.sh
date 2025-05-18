#!/bin/bash

# Security Scan Script
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check required environment variables
if [ -z "$WIZ_API_TOKEN" ]; then
    log "Error: WIZ_API_TOKEN environment variable is not set"
    exit 1
fi

if [ -z "$SEEKER_API_TOKEN" ]; then
    log "Error: SEEKER_API_TOKEN environment variable is not set"
    exit 1
fi

# Function to run Wiz scan
run_wiz_scan() {
    local tfplan_path=$1
    log "Running Wiz security scan on Terraform plan..."
    
    # Convert tfplan to JSON
    terraform show -json "$tfplan_path" > tfplan.json
    
    # Run Wiz scan
    curl -X POST "https://api.wiz.io/v1/scan" \
        -H "Authorization: Bearer $WIZ_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d @tfplan.json > wiz_scan_result.json
    
    # Check for critical issues
    if jq -e '.critical_issues > 0' wiz_scan_result.json > /dev/null; then
        log "Error: Critical security issues found in the plan"
        cat wiz_scan_result.json
        exit 1
    fi
    
    log "Wiz scan completed successfully"
}

# Function to run Seeker scan
run_seeker_scan() {
    local target=$1
    local scan_type=$2
    log "Running Seeker security scan on $target..."
    
    curl -X POST "https://api.seeker.io/v1/scan" \
        -H "Authorization: Bearer $SEEKER_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"target\": \"$target\", \"scan_type\": \"$scan_type\"}" > seeker_scan_result.json
    
    if ! jq -e '.status == "success"' seeker_scan_result.json > /dev/null; then
        log "Error: Seeker scan failed"
        cat seeker_scan_result.json
        exit 1
    fi
    
    log "Seeker scan completed successfully"
}

# Main execution
if [ "$1" = "terraform" ] && [ -n "$2" ]; then
    run_wiz_scan "$2"
elif [ "$1" = "api" ] && [ -n "$2" ]; then
    run_seeker_scan "$2" "api"
elif [ "$1" = "web" ] && [ -n "$2" ]; then
    run_seeker_scan "$2" "web"
else
    log "Error: Invalid arguments"
    echo "Usage: $0 terraform <tfplan-path>"
    echo "       $0 api <api-endpoint>"
    echo "       $0 web <web-url>"
    exit 1
fi

# Cleanup
rm -f tfplan.json wiz_scan_result.json seeker_scan_result.json 