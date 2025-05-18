#!/bin/bash

# Script to analyze Terraform plan files for high-risk changes
# This script parses a Terraform plan file and checks for potentially dangerous changes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_FILE=".terraform-plan-check.yaml"
OUTPUT_FORMAT="text"  # text, json, or yaml
FAIL_ON_HIGH_RISK=false
VERBOSE=false

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Function to print errors
print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Function to print debug messages
print_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}DEBUG: $1${NC}"
    fi
}

# Function to check if required commands are available
check_requirements() {
    local missing_commands=()
    
    for cmd in terraform jq yq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        exit 1
    fi
}

# Function to load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        print_debug "Loading configuration from $CONFIG_FILE"
        OUTPUT_FORMAT=$(yq e '.output_format // "text"' "$CONFIG_FILE")
        FAIL_ON_HIGH_RISK=$(yq e '.fail_on_high_risk // false' "$CONFIG_FILE")
        VERBOSE=$(yq e '.verbose // false' "$CONFIG_FILE")
    fi
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --fail-on-high-risk)
                FAIL_ON_HIGH_RISK=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                PLAN_FILE="$1"
                shift
                ;;
        esac
    done
}

# Function to show help
show_help() {
    echo "Usage: $0 [options] <terraform-plan-file>"
    echo
    echo "Options:"
    echo "  -f, --format FORMAT    Output format (text, json, yaml)"
    echo "  -c, --config FILE      Configuration file path"
    echo "  --fail-on-high-risk    Fail on high-risk changes"
    echo "  -v, --verbose          Enable verbose output"
    echo "  -h, --help             Show this help message"
}

# Function to check for resource deletions
check_resource_deletions() {
    local plan_json="$1"
    local -n total_changes=$2
    local -n high_risk_changes=$3
    local -n critical_changes=$4
    
    print_header "Checking for Resource Deletions"
    
    # Critical resources that should never be deleted
    local critical_resources=(
        "aws_dynamodb_table"
        "aws_rds_cluster"
        "aws_s3_bucket"
        "aws_kms_key"
        "aws_vpc"
        "aws_route53_zone"
    )
    
    # Get all resource deletions
    local deletions
    deletions=$(jq -r '.resource_changes[] | select(.change.actions[] == "delete") | .address' "$plan_json")
    
    if [ ! -z "$deletions" ]; then
        print_warning "Found resource deletions:"
        echo "$deletions" | while read -r resource; do
            local is_critical=false
            for critical in "${critical_resources[@]}"; do
                if [[ "$resource" =~ ^$critical ]]; then
                    print_error "CRITICAL: Attempting to delete $resource"
                    critical_changes=$((critical_changes + 1))
                    is_critical=true
                    break
                fi
            done
            
            if [ "$is_critical" = false ]; then
                print_warning "Deleting $resource"
                high_risk_changes=$((high_risk_changes + 1))
            fi
        done
    fi
}

# Function to check security group changes
check_security_groups() {
    local plan_json="$1"
    local -n total_changes=$2
    local -n high_risk_changes=$3
    local -n critical_changes=$4
    
    print_header "Checking Security Group Changes"
    
    # Get all security group changes
    local sg_changes
    sg_changes=$(jq -r '.resource_changes[] | select(.address | startswith("aws_security_group")) | .address' "$plan_json")
    
    if [ ! -z "$sg_changes" ]; then
        print_warning "Found security group changes:"
        echo "$sg_changes" | while read -r sg; do
            # Check for inbound rule changes
            local inbound_changes
            inbound_changes=$(jq -r --arg sg "$sg" '.resource_changes[] | select(.address == $sg) | .change.before.ingress' "$plan_json")
            if [ ! -z "$inbound_changes" ]; then
                print_error "CRITICAL: Modifying inbound rules for $sg"
                critical_changes=$((critical_changes + 1))
            fi
            
            # Check for security group deletion
            local is_deletion
            is_deletion=$(jq -r --arg sg "$sg" '.resource_changes[] | select(.address == $sg) | .change.actions[] | select(. == "delete")' "$plan_json")
            if [ ! -z "$is_deletion" ]; then
                print_error "CRITICAL: Attempting to delete security group $sg"
                critical_changes=$((critical_changes + 1))
            fi
        done
    fi
}

# Function to check IAM changes
check_iam_changes() {
    local plan_json="$1"
    local -n total_changes=$2
    local -n high_risk_changes=$3
    local -n critical_changes=$4
    
    print_header "Checking IAM Changes"
    
    # Get all IAM changes
    local iam_changes
    iam_changes=$(jq -r '.resource_changes[] | select(.address | startswith("aws_iam")) | .address' "$plan_json")
    
    if [ ! -z "$iam_changes" ]; then
        print_warning "Found IAM changes:"
        echo "$iam_changes" | while read -r iam; do
            # Check for critical IAM changes
            if [[ "$iam" =~ ^aws_iam_role_policy|^aws_iam_policy|^aws_iam_user_policy ]]; then
                print_error "CRITICAL: Modifying IAM permissions: $iam"
                critical_changes=$((critical_changes + 1))
            elif [[ "$iam" =~ ^aws_iam_role|^aws_iam_user ]]; then
                print_warning "Modifying IAM resource: $iam"
                high_risk_changes=$((high_risk_changes + 1))
            fi
        done
    fi
}

# Function to check database changes
check_database_changes() {
    local plan_json="$1"
    local -n total_changes=$2
    local -n high_risk_changes=$3
    local -n critical_changes=$4
    
    print_header "Checking Database Changes"
    
    # Get all database changes
    local db_changes
    db_changes=$(jq -r '.resource_changes[] | select(.address | startswith("aws_db_instance") or startswith("aws_rds_cluster")) | .address' "$plan_json")
    
    if [ ! -z "$db_changes" ]; then
        print_warning "Found database changes:"
        echo "$db_changes" | while read -r db; do
            # Check for instance type changes
            local instance_changes
            instance_changes=$(jq -r --arg db "$db" '.resource_changes[] | select(.address == $db) | .change.before.instance_class' "$plan_json")
            if [ ! -z "$instance_changes" ]; then
                print_error "CRITICAL: Modifying database instance type for $db"
                critical_changes=$((critical_changes + 1))
            fi
            
            # Check for parameter group changes
            local param_changes
            param_changes=$(jq -r --arg db "$db" '.resource_changes[] | select(.address == $db) | .change.before.parameter_group_name' "$plan_json")
            if [ ! -z "$param_changes" ]; then
                print_warning "Modifying database parameter group for $db"
                high_risk_changes=$((high_risk_changes + 1))
            fi
        done
    fi
}

# Function to check VPC changes
check_vpc_changes() {
    local plan_json="$1"
    local -n total_changes=$2
    local -n high_risk_changes=$3
    local -n critical_changes=$4
    
    print_header "Checking VPC Changes"
    
    # Get all VPC changes
    local vpc_changes
    vpc_changes=$(jq -r '.resource_changes[] | select(.address | startswith("aws_vpc")) | .address' "$plan_json")
    
    if [ ! -z "$vpc_changes" ]; then
        print_error "CRITICAL: Modifying VPC configuration"
        echo "$vpc_changes" | while read -r vpc; do
            critical_changes=$((critical_changes + 1))
        done
    fi
    
    # Check for subnet changes
    local subnet_changes
    subnet_changes=$(jq -r '.resource_changes[] | select(.address | startswith("aws_subnet")) | .address' "$plan_json")
    if [ ! -z "$subnet_changes" ]; then
        print_warning "Found subnet changes:"
        echo "$subnet_changes" | while read -r subnet; do
            high_risk_changes=$((high_risk_changes + 1))
        done
    fi
}

# Function to check KMS changes
check_kms_changes() {
    local plan_json="$1"
    local -n total_changes=$2
    local -n high_risk_changes=$3
    local -n critical_changes=$4
    
    print_header "Checking KMS Changes"
    
    # Get all KMS changes
    local kms_changes
    kms_changes=$(jq -r '.resource_changes[] | select(.address | startswith("aws_kms_key")) | .address' "$plan_json")
    
    if [ ! -z "$kms_changes" ]; then
        print_error "CRITICAL: Modifying KMS keys"
        echo "$kms_changes" | while read -r kms; do
            critical_changes=$((critical_changes + 1))
        done
    fi
}

# Function to generate JSON output
generate_json_output() {
    local total_changes=$1
    local high_risk_changes=$2
    local critical_changes=$3
    
    jq -n \
        --arg total "$total_changes" \
        --arg high_risk "$high_risk_changes" \
        --arg critical "$critical_changes" \
        '{
            "total_changes": $total,
            "high_risk_changes": $high_risk,
            "critical_changes": $critical,
            "status": (if $critical != "0" then "critical" elif $high_risk != "0" then "high_risk" else "safe" end)
        }'
}

# Function to generate YAML output
generate_yaml_output() {
    local total_changes=$1
    local high_risk_changes=$2
    local critical_changes=$3
    
    echo "total_changes: $total_changes"
    echo "high_risk_changes: $high_risk_changes"
    echo "critical_changes: $critical_changes"
    echo "status: $(if [ "$critical_changes" -gt 0 ]; then echo "critical"; elif [ "$high_risk_changes" -gt 0 ]; then echo "high_risk"; else echo "safe"; fi)"
}

# Main script execution
main() {
    # Check requirements
    check_requirements
    
    # Parse arguments
    parse_args "$@"
    
    # Load configuration
    load_config
    
    # Check if plan file is provided
    if [ -z "${PLAN_FILE:-}" ]; then
        print_error "No Terraform plan file provided"
        show_help
        exit 1
    fi
    
    # Check if plan file exists
    if [ ! -f "$PLAN_FILE" ]; then
        print_error "Plan file not found: $PLAN_FILE"
        exit 1
    fi
    
    # Convert plan to JSON for easier parsing
    PLAN_JSON="${PLAN_FILE}.json"
    print_debug "Converting plan to JSON format"
    terraform show -json "$PLAN_FILE" > "$PLAN_JSON"
    
    # Initialize counters
    TOTAL_CHANGES=0
    HIGH_RISK_CHANGES=0
    CRITICAL_CHANGES=0
    
    print_header "Analyzing Terraform Plan"
    
    # Run all checks
    check_resource_deletions "$PLAN_JSON" TOTAL_CHANGES HIGH_RISK_CHANGES CRITICAL_CHANGES
    check_security_groups "$PLAN_JSON" TOTAL_CHANGES HIGH_RISK_CHANGES CRITICAL_CHANGES
    check_iam_changes "$PLAN_JSON" TOTAL_CHANGES HIGH_RISK_CHANGES CRITICAL_CHANGES
    check_database_changes "$PLAN_JSON" TOTAL_CHANGES HIGH_RISK_CHANGES CRITICAL_CHANGES
    check_vpc_changes "$PLAN_JSON" TOTAL_CHANGES HIGH_RISK_CHANGES CRITICAL_CHANGES
    check_kms_changes "$PLAN_JSON" TOTAL_CHANGES HIGH_RISK_CHANGES CRITICAL_CHANGES
    
    # Calculate total changes
    TOTAL_CHANGES=$(jq -r '.resource_changes | length' "$PLAN_JSON")
    
    # Print summary based on output format
    case "$OUTPUT_FORMAT" in
        "json")
            generate_json_output "$TOTAL_CHANGES" "$HIGH_RISK_CHANGES" "$CRITICAL_CHANGES"
            ;;
        "yaml")
            generate_yaml_output "$TOTAL_CHANGES" "$HIGH_RISK_CHANGES" "$CRITICAL_CHANGES"
            ;;
        *)
            print_header "Change Summary"
            echo "Total changes: $TOTAL_CHANGES"
            echo "High-risk changes: $HIGH_RISK_CHANGES"
            echo "Critical changes: $CRITICAL_CHANGES"
            ;;
    esac
    
    # Clean up
    rm "$PLAN_JSON"
    
    # Exit with appropriate status
    if [ $CRITICAL_CHANGES -gt 0 ]; then
        print_error "Critical changes detected. Manual review required."
        exit 1
    elif [ $HIGH_RISK_CHANGES -gt 0 ] && [ "$FAIL_ON_HIGH_RISK" = true ]; then
        print_warning "High-risk changes detected. Please review carefully."
        exit 2
    else
        print_success "No high-risk changes detected."
        exit 0
    fi
}

# Run main function with all arguments
main "$@" 