#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/security.log"
SCAN_DIR="../src"
REPORT_DIR="../artifacts/security-reports"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

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

# Create report directory
mkdir -p "$REPORT_DIR"

# Run npm audit
run_npm_audit() {
    log "Running npm audit..."
    npm audit > "$REPORT_DIR/npm-audit-$TIMESTAMP.txt" 2>&1 || true
}

# Run Snyk security scan
run_snyk_scan() {
    log "Running Snyk security scan..."
    if command -v snyk &> /dev/null; then
        snyk test > "$REPORT_DIR/snyk-scan-$TIMESTAMP.txt" 2>&1 || true
    else
        log "WARNING: Snyk not installed. Skipping Snyk scan."
    fi
}

# Run dependency check
run_dependency_check() {
    log "Running dependency check..."
    if command -v dependency-check &> /dev/null; then
        dependency-check --scan "$SCAN_DIR" --format HTML --out "$REPORT_DIR/dependency-check-$TIMESTAMP.html" || true
    else
        log "WARNING: OWASP Dependency Check not installed. Skipping dependency check."
    fi
}

# Run code quality checks
run_code_quality_checks() {
    log "Running code quality checks..."
    
    # ESLint
    if command -v eslint &> /dev/null; then
        log "Running ESLint..."
        eslint "$SCAN_DIR" > "$REPORT_DIR/eslint-$TIMESTAMP.txt" 2>&1 || true
    fi
    
    # SonarQube Scanner
    if command -v sonar-scanner &> /dev/null; then
        log "Running SonarQube Scanner..."
        sonar-scanner \
            -Dsonar.projectKey=audit-system \
            -Dsonar.sources="$SCAN_DIR" \
            -Dsonar.host.url=http://localhost:9000 \
            -Dsonar.login=admin \
            -Dsonar.password=admin > "$REPORT_DIR/sonar-scan-$TIMESTAMP.txt" 2>&1 || true
    else
        log "WARNING: SonarQube Scanner not installed. Skipping SonarQube scan."
    fi
}

# Check for sensitive data
check_sensitive_data() {
    log "Checking for sensitive data..."
    
    # Check for API keys
    grep -r "api[_-]key" "$SCAN_DIR" > "$REPORT_DIR/sensitive-data-$TIMESTAMP.txt" 2>&1 || true
    
    # Check for passwords
    grep -r "password" "$SCAN_DIR" >> "$REPORT_DIR/sensitive-data-$TIMESTAMP.txt" 2>&1 || true
    
    # Check for AWS credentials
    grep -r "aws[_-]access[_-]key" "$SCAN_DIR" >> "$REPORT_DIR/sensitive-data-$TIMESTAMP.txt" 2>&1 || true
    grep -r "aws[_-]secret[_-]key" "$SCAN_DIR" >> "$REPORT_DIR/sensitive-data-$TIMESTAMP.txt" 2>&1 || true
}

# Main security scan
log "Starting security scan..."

# Run all security checks
run_npm_audit
run_snyk_scan
run_dependency_check
run_code_quality_checks
check_sensitive_data

# Generate summary report
log "Generating summary report..."
{
    echo "Security Scan Summary"
    echo "===================="
    echo "Timestamp: $TIMESTAMP"
    echo ""
    echo "Reports generated:"
    ls -l "$REPORT_DIR" | grep "$TIMESTAMP"
} > "$REPORT_DIR/summary-$TIMESTAMP.txt"

log "Security scan completed. Reports available in $REPORT_DIR" 