#!/bin/bash

# Exit on error
set -e

# Configuration
LOG_FILE="../artifacts/health.log"
ALERT_EMAIL="admin@example.com"
HEALTH_CHECK_INTERVAL=300  # 5 minutes
MAX_RETRIES=3

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log "ERROR: An error occurred on line $1"
    send_alert "Health check failed: Error on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Send alert function
send_alert() {
    local message="$1"
    log "Sending alert: $message"
    # Implement your alert mechanism here (email, Slack, etc.)
    # Example: mail -s "Health Check Alert" "$ALERT_EMAIL" <<< "$message"
}

# Check application health
check_application_health() {
    log "Checking application health..."
    
    # Check if application is responding
    if ! curl -s http://localhost:3000/health > /dev/null; then
        log "ERROR: Application health check failed"
        return 1
    fi
    
    # Check database connection
    if ! curl -s http://localhost:3000/health/db > /dev/null; then
        log "ERROR: Database health check failed"
        return 1
    fi
    
    # Check disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log "WARNING: Disk usage is above 90%"
        send_alert "High disk usage: $disk_usage%"
    fi
    
    # Check memory usage
    local memory_usage=$(free | awk '/Mem:/ {print $3/$2 * 100.0}')
    if (( $(echo "$memory_usage > 90" | bc -l) )); then
        log "WARNING: Memory usage is above 90%"
        send_alert "High memory usage: $memory_usage%"
    fi
    
    return 0
}

# Check system resources
check_system_resources() {
    log "Checking system resources..."
    
    # Check CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ')
    if (( $(echo "$cpu_load > 5" | bc -l) )); then
        log "WARNING: High CPU load: $cpu_load"
        send_alert "High CPU load: $cpu_load"
    fi
    
    # Check number of processes
    local process_count=$(ps aux | wc -l)
    if [ "$process_count" -gt 1000 ]; then
        log "WARNING: High number of processes: $process_count"
        send_alert "High number of processes: $process_count"
    fi
    
    return 0
}

# Main health check loop
while true; do
    log "Starting health check cycle..."
    
    # Run health checks
    if ! check_application_health; then
        send_alert "Application health check failed"
    fi
    
    if ! check_system_resources; then
        send_alert "System resources check failed"
    fi
    
    log "Health check cycle completed"
    
    # Wait for next check
    sleep "$HEALTH_CHECK_INTERVAL"
done 