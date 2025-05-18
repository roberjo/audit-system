# CI/CD Pipeline Documentation

## Overview

The Audit System uses a comprehensive CI/CD pipeline that combines GitHub Actions for build and test automation, JFrog Artifactory for artifact management, and Harness for deployment orchestration and security scanning.

## Pipeline Architecture

### 1. GitHub Actions Workflows

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

#### Code Quality Workflow
```yaml
name: Code Quality

on:
  pull_request:
    branches: [ main, develop ]

jobs:
  code-quality:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: SonarQube Scan
      uses: SonarSource/sonarqube-scan-action@master
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
    
    - name: Check Code Quality Gate
      uses: SonarSource/sonarqube-quality-gate-action@master
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
```

### 2. Artifactory Configuration

#### Repository Structure
```
audit-system/
├── main/
│   ├── lambda-dotnet/
│   ├── lambda-python/
│   ├── frontend/
│   └── infrastructure/
├── develop/
│   ├── lambda-dotnet/
│   ├── lambda-python/
│   ├── frontend/
│   └── infrastructure/
└── releases/
    └── v1.0.0/
```

#### Retention Policy
```yaml
retention:
  maxUniqueSnapshots: 10
  maxUniqueReleases: 5
  deleteUnusedArtifacts: true
  excludeBuilds: false
```

### 3. Harness Pipeline Configuration

#### Infrastructure Pipeline
```yaml
pipeline:
  name: audit-system-infrastructure
  identifier: audit_system_infrastructure
  stages:
    - stage:
        name: terraform-plan
        identifier: terraform_plan
        type: CI
        spec:
          steps:
            - step:
                name: terraform-init
                identifier: terraform_init
                type: Run
                spec:
                  shell: PowerShell
                  command: |
                    terraform init
                    terraform plan -out=tfplan
    
    - stage:
        name: security-scan
        identifier: security_scan
        type: CI
        spec:
          steps:
            - step:
                name: wiz-scan
                identifier: wiz_scan
                type: Run
                spec:
                  shell: PowerShell
                  command: |
                    wiz-cli scan --project audit-system
    
            - step:
                name: seeker-scan
                identifier: seeker_scan
                type: Run
                spec:
                  shell: PowerShell
                  command: |
                    seeker-cli scan --project audit-system
    
    - stage:
        name: terraform-apply
        identifier: terraform_apply
        type: CD
        spec:
          steps:
            - step:
                name: check-terraform-plan
                identifier: check_terraform_plan
                type: Run
                spec:
                  shell: PowerShell
                  command: |
                    ./scripts/check-terraform-plan.ps1
    
            - step:
                name: terraform-apply
                identifier: terraform_apply
                type: Run
                spec:
                  shell: PowerShell
                  command: |
                    terraform apply tfplan
```

### 4. Terraform Plan Check Script (Bash Version)

```bash
#!/bin/bash

# check-terraform-plan.sh

PLAN_FILE=${1:-"tfplan"}
ALERT_WEBHOOK=${2:-$ALERT_WEBHOOK}

# Convert terraform plan to JSON
PLAN_JSON=$(terraform show -json "$PLAN_FILE")

# Initialize counters
CREATE_COUNT=0
UPDATE_COUNT=0
DELETE_COUNT=0

# Analyze plan
while IFS= read -r line; do
    if [[ $line == *"\"actions\":[\"create\"]"* ]]; then
        ((CREATE_COUNT++))
    elif [[ $line == *"\"actions\":[\"update\"]"* ]]; then
        ((UPDATE_COUNT++))
    elif [[ $line == *"\"actions\":[\"delete\"]"* ]]; then
        ((DELETE_COUNT++))
    fi
done <<< "$PLAN_JSON"

# Check for potential issues
ISSUES=()

# Check for resource deletion
if [ "$DELETE_COUNT" -gt 0 ]; then
    ISSUES+=("WARNING: $DELETE_COUNT resources will be deleted")
fi

# Check for database changes
if echo "$PLAN_JSON" | grep -q "\"type\":\".*db.*\""; then
    ISSUES+=("WARNING: Database changes detected")
fi

# Check for security group changes
if echo "$PLAN_JSON" | grep -q "\"type\":\".*security_group.*\""; then
    ISSUES+=("WARNING: Security group changes detected")
fi

# Send alert if issues found
if [ ${#ISSUES[@]} -gt 0 ]; then
    MESSAGE="Terraform Plan Issues Detected:\n${ISSUES[*]}"
    curl -X POST -H "Content-Type: application/json" -d "{\"text\":\"$MESSAGE\"}" "$ALERT_WEBHOOK"
    
    echo "Terraform plan contains potential issues. Check alerts for details."
    exit 1
fi

echo "Terraform plan check passed successfully."
exit 0
```

### 5. Release and Deploy Workflow

```yaml
name: Release and Deploy

on:
  push:
    branches: [ main, develop ]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'develop'
        type: choice
        options:
          - develop
          - staging
          - production

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    
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
        mkdir -p artifacts
        zip -r artifacts/lambda-dotnet.zip ./bin/Release/net8.0/publish/*
        zip -r artifacts/frontend.zip ./dist/*
    
    - name: Generate Version
      id: version
      run: |
        if [[ $GITHUB_REF == refs/tags/* ]]; then
          VERSION=${GITHUB_REF#refs/tags/}
        else
          VERSION=$(date +'%Y.%m.%d')-$(echo $GITHUB_SHA | cut -c1-7)
        fi
        echo "VERSION=$VERSION" >> $GITHUB_ENV
        echo "version=$VERSION" >> $GITHUB_OUTPUT
    
    - name: Upload to Artifactory
      uses: jfrog/setup-jfrog-cli@v2
      with:
        version: latest
    
    - name: Configure Artifactory
      run: |
        jf c add --url ${{ secrets.ARTIFACTORY_URL }} \
                 --user ${{ secrets.ARTIFACTORY_USER }} \
                 --password ${{ secrets.ARTIFACTORY_PASSWORD }}
    
    - name: Upload Artifacts
      run: |
        # Upload to release repository
        jf rt upload ./artifacts/* audit-system/releases/${{ env.VERSION }}/
        
        # Upload to environment-specific repository
        jf rt upload ./artifacts/* audit-system/${{ github.event.inputs.environment || 'develop' }}/latest/
    
    - name: Trigger Harness Pipeline
      if: success()
      run: |
        curl -X POST \
          -H "Content-Type: application/json" \
          -H "x-api-key: ${{ secrets.HARNESS_API_KEY }}" \
          -d "{
            \"application\": \"audit-system\",
            \"environment\": \"${{ github.event.inputs.environment || 'develop' }}\",
            \"version\": \"${{ env.VERSION }}\"
          }" \
          "${{ secrets.HARNESS_WEBHOOK_URL }}"
```

### 6. Build and Package Script (Bash Version)

```bash
#!/bin/bash

# build-and-package.sh

# Exit on error
set -e

# Create artifacts directory
mkdir -p artifacts

# Build .NET components
echo "Building .NET components..."
dotnet publish -c Release

# Build frontend
echo "Building frontend..."
npm run build

# Package Lambda functions
echo "Packaging Lambda functions..."
zip -r artifacts/lambda-dotnet.zip ./bin/Release/net8.0/publish/*
zip -r artifacts/lambda-python.zip ./python/src/*

# Package frontend
echo "Packaging frontend..."
zip -r artifacts/frontend.zip ./dist/*

# Generate version
if [[ $GITHUB_REF == refs/tags/* ]]; then
    VERSION=${GITHUB_REF#refs/tags/}
else
    VERSION=$(date +'%Y.%m.%d')-$(echo $GITHUB_SHA | cut -c1-7)
fi

# Upload to Artifactory
echo "Uploading to Artifactory..."
jf rt upload ./artifacts/* audit-system/releases/$VERSION/
jf rt upload ./artifacts/* audit-system/$ENVIRONMENT/latest/

echo "Build and package completed successfully."
echo "Version: $VERSION"
```

### 7. Test Runner Script (Bash Version)

```bash
#!/bin/bash

# test-runner.sh

# Exit on error
set -e

# Run .NET tests
echo "Running .NET tests..."
dotnet test --collect:"XPlat Code Coverage"

# Run JavaScript tests
echo "Running JavaScript tests..."
npm run test

# Run Python tests
echo "Running Python tests..."
pytest --cov=./python

# Upload coverage reports
echo "Uploading coverage reports..."
bash <(curl -s https://codecov.io/bash) -t $CODECOV_TOKEN

echo "Tests completed successfully."
```

### 8. Deployment Trigger Script (Bash Version)

```bash
#!/bin/bash

# deploy-trigger.sh

# Exit on error
set -e

# Validate inputs
if [ -z "$HARNESS_API_KEY" ]; then
    echo "Error: HARNESS_API_KEY is required"
    exit 1
fi

if [ -z "$HARNESS_WEBHOOK_URL" ]; then
    echo "Error: HARNESS_WEBHOOK_URL is required"
    exit 1
fi

# Default to develop if environment not specified
ENVIRONMENT=${1:-"develop"}
VERSION=${2:-"latest"}

# Trigger Harness pipeline
echo "Triggering deployment to $ENVIRONMENT environment..."
curl -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: $HARNESS_API_KEY" \
  -d "{
    \"application\": \"audit-system\",
    \"environment\": \"$ENVIRONMENT\",
    \"version\": \"$VERSION\"
  }" \
  "$HARNESS_WEBHOOK_URL"

echo "Deployment trigger completed successfully."
```

## Pipeline Triggers

### 1. GitHub Actions Triggers
- Push to main/develop branches
- Pull request creation/updates
- Manual workflow dispatch

### 2. Harness Pipeline Triggers
- Successful GitHub Actions build
- Manual trigger
- Scheduled runs (for security scans)

## Security Scanning

### 1. Wiz Vulnerability Scan
- Infrastructure as Code scanning
- Container image scanning
- Cloud configuration scanning
- Compliance checks

### 2. Seeker Application Scan
- SAST (Static Application Security Testing)
- DAST (Dynamic Application Security Testing)
- Dependency scanning
- Custom rule validation

## Monitoring and Alerts

### 1. Pipeline Metrics
- Build success/failure rates
- Test coverage trends
- Security scan results
- Deployment frequency

### 2. Alert Channels
- Slack notifications
- Email alerts
- PagerDuty integration
- Custom webhook endpoints

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