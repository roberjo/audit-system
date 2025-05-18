#!/bin/bash

# Test Runner Script
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to run unit tests
run_unit_tests() {
    local component=$1
    log "Running unit tests for $component..."
    
    if [ -d "src/$component" ]; then
        cd "src/$component"
        npm test
        cd - > /dev/null
    else
        log "Error: Component directory not found: src/$component"
        exit 1
    fi
}

# Function to run integration tests
run_integration_tests() {
    local component=$1
    log "Running integration tests for $component..."
    
    if [ -d "tests/integration/$component" ]; then
        cd "tests/integration/$component"
        npm test
        cd - > /dev/null
    else
        log "Error: Integration test directory not found: tests/integration/$component"
        exit 1
    fi
}

# Function to run end-to-end tests
run_e2e_tests() {
    log "Running end-to-end tests..."
    
    if [ -d "tests/e2e" ]; then
        cd "tests/e2e"
        npm test
        cd - > /dev/null
    else
        log "Error: E2E test directory not found: tests/e2e"
        exit 1
    fi
}

# Function to run performance tests
run_performance_tests() {
    local component=$1
    log "Running performance tests for $component..."
    
    if [ -d "tests/performance/$component" ]; then
        cd "tests/performance/$component"
        npm test
        cd - > /dev/null
    else
        log "Error: Performance test directory not found: tests/performance/$component"
        exit 1
    fi
}

# Main execution
case "$1" in
    "unit")
        if [ -z "$2" ]; then
            log "Error: Component name required for unit tests"
            echo "Usage: $0 unit <component-name>"
            exit 1
        fi
        run_unit_tests "$2"
        ;;
    "integration")
        if [ -z "$2" ]; then
            log "Error: Component name required for integration tests"
            echo "Usage: $0 integration <component-name>"
            exit 1
        fi
        run_integration_tests "$2"
        ;;
    "e2e")
        run_e2e_tests
        ;;
    "performance")
        if [ -z "$2" ]; then
            log "Error: Component name required for performance tests"
            echo "Usage: $0 performance <component-name>"
            exit 1
        fi
        run_performance_tests "$2"
        ;;
    "all")
        log "Running all tests..."
        run_unit_tests "frontend"
        run_unit_tests "lambda"
        run_integration_tests "api"
        run_integration_tests "lambda"
        run_e2e_tests
        run_performance_tests "api"
        run_performance_tests "frontend"
        ;;
    *)
        log "Error: Invalid test type"
        echo "Usage: $0 <test-type> [component-name]"
        echo "Test types: unit, integration, e2e, performance, all"
        exit 1
        ;;
esac

log "All tests completed successfully" 