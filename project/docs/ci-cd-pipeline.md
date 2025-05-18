# CI/CD Pipeline Documentation

## Overview

This document explains how code changes are automatically built, tested, and deployed in the Audit System. It details the integration of GitHub Actions for continuous integration, JFrog Artifactory for artifact management, and Harness for deployment orchestration. The pipeline ensures code quality through automated testing, security scanning, and controlled deployments across development, staging, and production environments.

## Environment Configuration

### 1. Required Secrets

#### GitHub Secrets
```yaml
# Required for GitHub Actions
ARTIFACTORY_URL: "https://artifactory.example.com"
ARTIFACTORY_USER: "ci-user"
ARTIFACTORY_PASSWORD: "encrypted-password"
CODECOV_TOKEN: "encrypted-token"
SONAR_TOKEN: "encrypted-token"
SONAR_HOST_URL: "https://sonar.example.com"
HARNESS_API_KEY: "encrypted-api-key"
HARNESS_WEBHOOK_URL: "https://harness.example.com/api/webhooks/deploy"
```

#### Environment Variables
```yaml
# Development
DEV_AWS_ACCESS_KEY: "encrypted-key"
DEV_AWS_SECRET_KEY: "encrypted-secret"
DEV_VAULT_ADDR: "https://vault-dev.example.com"
DEV_VAULT_TOKEN: "encrypted-token"

# Staging
STAGING_AWS_ACCESS_KEY: "encrypted-key"
STAGING_AWS_SECRET_KEY: "encrypted-secret"
STAGING_VAULT_ADDR: "https://vault-staging.example.com"
STAGING_VAULT_TOKEN: "encrypted-token"

# Production
PROD_AWS_ACCESS_KEY: "encrypted-key"
PROD_AWS_SECRET_KEY: "encrypted-secret"
PROD_VAULT_ADDR: "https://vault-prod.example.com"
PROD_VAULT_TOKEN: "encrypted-token"
```

### 2. Artifactory Configuration

#### Repository Structure
```
audit-system/
├── main/
│   ├── lambda-dotnet/
│   │   ├── latest/
│   │   └── versions/
│   ├── lambda-python/
│   │   ├── latest/
│   │   └── versions/
│   ├── frontend/
│   │   ├── latest/
│   │   └── versions/
│   └── infrastructure/
│       ├── latest/
│       └── versions/
├── develop/
│   └── [same structure as main]
└── releases/
    └── v1.0.0/
        ├── lambda-dotnet/
        ├── lambda-python/
        ├── frontend/
        └── infrastructure/
```

#### Repository Permissions
```yaml
permissions:
  develop:
    read: ["developers", "qa"]
    write: ["developers"]
    deploy: ["developers", "qa"]
  main:
    read: ["developers", "qa", "operations"]
    write: ["developers", "operations"]
    deploy: ["operations"]
  releases:
    read: ["developers", "qa", "operations", "support"]
    write: ["operations"]
    deploy: ["operations"]
```

#### Retention Policy
```yaml
retention:
  develop:
    maxUniqueSnapshots: 10
    maxUniqueReleases: 5
    deleteUnusedArtifacts: true
    excludeBuilds: false
  main:
    maxUniqueSnapshots: 20
    maxUniqueReleases: 10
    deleteUnusedArtifacts: false
    excludeBuilds: true
  releases:
    maxUniqueSnapshots: 50
    maxUniqueReleases: 25
    deleteUnusedArtifacts: false
    excludeBuilds: true
```

### 3. Harness Pipeline Configuration

#### Pipeline Variables
```yaml
variables:
  - name: ENVIRONMENT
    type: String
    required: true
    allowedValues: ["develop", "staging", "production"]
  - name: VERSION
    type: String
    required: true
  - name: AWS_REGION
    type: String
    defaultValue: "us-east-1"
  - name: ENABLE_SECURITY_SCAN
    type: Boolean
    defaultValue: true
```

#### Pipeline Stages
```yaml
stages:
  - name: validate
    type: CI
    steps:
      - name: validate-terraform
        type: Run
        spec:
          shell: PowerShell
          command: |
            terraform init
            terraform validate
            terraform plan -out=tfplan

  - name: security-scan
    type: CI
    steps:
      - name: wiz-scan
        type: Run
        spec:
          shell: PowerShell
          command: |
            wiz-cli scan --project audit-system --output json > wiz-report.json
            # Parse and validate results
            ./scripts/validate-wiz-report.ps1

      - name: seeker-scan
        type: Run
        spec:
          shell: PowerShell
          command: |
            seeker-cli scan --project audit-system --output json > seeker-report.json
            # Parse and validate results
            ./scripts/validate-seeker-report.ps1

  - name: deploy
    type: CD
    steps:
      - name: check-terraform-plan
        type: Run
        spec:
          shell: PowerShell
          command: |
            ./scripts/check-terraform-plan.ps1

      - name: terraform-apply
        type: Run
        spec:
          shell: PowerShell
          command: |
            terraform apply tfplan

      - name: verify-deployment
        type: Run
        spec:
          shell: PowerShell
          command: |
            ./scripts/verify-deployment.ps1
```

## Implementation Steps

### 1. Initial Setup

#### GitHub Repository Setup
```bash
# Create repository
gh repo create audit-system --private --description "Audit System for Wealth Management"

# Set up branch protection
gh api repos/:owner/:repo/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github.v3+json" \
  -f required_status_checks='{"strict":true,"contexts":["build-and-test","code-quality"]}' \
  -f enforce_admins=true \
  -f required_pull_request_reviews='{"dismissal_restrictions":{},"dismiss_stale_reviews":true,"require_code_owner_reviews":true,"required_approving_review_count":2}' \
  -f restrictions=null
```

#### Artifactory Setup
```bash
# Create repositories
jf rt repo-create audit-system-develop.json
jf rt repo-create audit-system-main.json
jf rt repo-create audit-system-releases.json

# Configure permissions
jf rt permission-create audit-system-permissions.json
```

#### Harness Setup
```bash
# Create application
harness-cli application create --name audit-system

# Create environments
harness-cli environment create --name develop --type NonProd
harness-cli environment create --name staging --type NonProd
harness-cli environment create --name production --type Prod

# Create pipeline
harness-cli pipeline create --name audit-system-infrastructure --yaml pipeline.yaml
```

### 2. Workflow Implementation

#### Build and Test Workflow
```yaml
name: Build and Test

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  build-and-test:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: '8.0.x'
    
    - name: Setup Node.js
      uses: actions/setup-node@v3
      with:
        node-version: '18.x'
    
    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'
    
    - name: Install Dependencies
      run: |
        dotnet restore
        npm install
        pip install -r requirements.txt
    
    - name: Run Linting
      run: |
        # ESLint for TypeScript/JavaScript
        npm run lint
        # Pylint for Python
        pylint ./python
        # .NET Code Analysis
        dotnet format --verify-no-changes
    
    - name: Run Tests
      run: |
        # .NET Tests
        dotnet test --collect:"XPlat Code Coverage"
        # JavaScript Tests
        npm run test
        # Python Tests
        pytest --cov=./python
    
    - name: Upload Coverage Reports
      uses: codecov/codecov-action@v3
      with:
        token: ${{ secrets.CODECOV_TOKEN }}
    
    - name: Build and Package
      run: |
        # .NET Build
        dotnet publish -c Release
        # Frontend Build
        npm run build
        # Package Lambda Functions
        Compress-Archive -Path ./bin/Release/net8.0/publish/* -DestinationPath ./artifacts/lambda-dotnet.zip
        Compress-Archive -Path ./dist/* -DestinationPath ./artifacts/frontend.zip
    
    - name: Upload to Artifactory
      uses: jfrog/setup-jfrog-cli@v2
      with:
        version: latest
    
    - name: Configure Artifactory
      run: |
        jf c add --url ${{ secrets.ARTIFACTORY_URL }} --user ${{ secrets.ARTIFACTORY_USER }} --password ${{ secrets.ARTIFACTORY_PASSWORD }}
    
    - name: Upload Artifacts
      run: |
        jf rt upload ./artifacts/* audit-system/${{ github.ref_name }}/${{ github.sha }}/
```

### 3. Security Scanning Implementation

#### Wiz Scan Configuration
```yaml
wiz:
  project: audit-system
  scanTypes:
    - iac
    - container
    - cloud
    - compliance
  thresholds:
    critical: 0
    high: 0
    medium: 5
    low: 10
  exclusions:
    - path: "**/test/**"
    - path: "**/docs/**"
```

#### Seeker Scan Configuration
```yaml
seeker:
  project: audit-system
  scanTypes:
    - sast
    - dast
    - dependency
  thresholds:
    critical: 0
    high: 0
    medium: 5
    low: 10
  exclusions:
    - path: "**/test/**"
    - path: "**/docs/**"
```

### 4. Deployment Verification

#### Deployment Check Script
```powershell
# verify-deployment.ps1

param(
    [string]$Environment = $env:ENVIRONMENT,
    [string]$Version = $env:VERSION
)

# Check Lambda functions
$lambdaFunctions = @(
    "audit-processor",
    "audit-enricher"
)

foreach ($function in $lambdaFunctions) {
    $status = aws lambda get-function --function-name $function
    if ($status.LastUpdateStatus -ne "Successful") {
        Write-Error "Lambda function $function deployment failed"
        exit 1
    }
}

# Check API Gateway
$apiStatus = aws apigateway get-rest-api --rest-api-id $env:API_ID
if ($apiStatus.status -ne "DEPLOYED") {
    Write-Error "API Gateway deployment failed"
    exit 1
}

# Check DynamoDB tables
$tables = @(
    "audit_events",
    "system_config"
)

foreach ($table in $tables) {
    $tableStatus = aws dynamodb describe-table --table-name $table
    if ($tableStatus.Table.TableStatus -ne "ACTIVE") {
        Write-Error "DynamoDB table $table is not active"
        exit 1
    }
}

Write-Host "Deployment verification completed successfully"
exit 0
```

## Monitoring and Alerts

### 1. Pipeline Metrics

#### GitHub Actions Metrics
```yaml
metrics:
  - name: build_success_rate
    type: gauge
    labels:
      - branch
      - workflow
  - name: test_coverage
    type: gauge
    labels:
      - language
      - branch
  - name: deployment_frequency
    type: counter
    labels:
      - environment
```

#### Harness Metrics
```yaml
metrics:
  - name: pipeline_success_rate
    type: gauge
    labels:
      - environment
      - pipeline
  - name: deployment_duration
    type: histogram
    labels:
      - environment
      - pipeline
```

### 2. Alert Configuration

#### Slack Alerts
```yaml
alerts:
  - name: pipeline_failure
    condition: build_success_rate < 0.95
    severity: critical
    channels:
      - slack: "#pipeline-alerts"
  - name: security_scan_failure
    condition: security_scan_score < 80
    severity: high
    channels:
      - slack: "#security-alerts"
  - name: deployment_failure
    condition: deployment_success_rate < 0.98
    severity: critical
    channels:
      - slack: "#deployment-alerts"
```

#### Email Alerts
```yaml
alerts:
  - name: critical_pipeline_failure
    condition: build_success_rate < 0.90
    severity: critical
    channels:
      - email: "devops@example.com"
  - name: security_vulnerability
    condition: security_scan_score < 70
    severity: high
    channels:
      - email: "security@example.com"
```

## Troubleshooting Guide

### 1. Common Issues

#### Build Failures
```yaml
solutions:
  - issue: "Dependency resolution failure"
    steps:
      - "Clear npm cache: npm cache clean --force"
      - "Delete node_modules: rm -rf node_modules"
      - "Reinstall dependencies: npm install"
  
  - issue: "Test failures"
    steps:
      - "Check test logs for specific failures"
      - "Verify test environment setup"
      - "Run tests locally to reproduce"
```

#### Deployment Failures
```yaml
solutions:
  - issue: "Terraform apply failure"
    steps:
      - "Check terraform plan for conflicts"
      - "Verify AWS credentials"
      - "Check resource limits and quotas"
  
  - issue: "Security scan failure"
    steps:
      - "Review scan reports for details"
      - "Check exclusion rules"
      - "Verify scan configuration"
```

### 2. Recovery Procedures

#### Pipeline Recovery
```yaml
procedures:
  - name: "Failed build recovery"
    steps:
      - "Identify failed step"
      - "Check build logs"
      - "Fix identified issue"
      - "Rerun failed workflow"
  
  - name: "Failed deployment recovery"
    steps:
      - "Check deployment logs"
      - "Verify infrastructure state"
      - "Rollback if necessary"
      - "Fix deployment issues"
      - "Redeploy"
```

## Best Practices

### 1. Code Quality
- Enforce linting rules
- Maintain minimum test coverage
- Regular dependency updates
- Code review requirements

### 2. Security
- Regular vulnerability scanning
- Secret scanning
- Infrastructure drift detection
- Compliance validation

### 3. Deployment
- Blue-green deployments
- Canary releases
- Automated rollbacks
- Environment promotion 