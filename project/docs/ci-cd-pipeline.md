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
  - name: TF_PLAN_CHECK_CONFIG
    type: String
    defaultValue: "./scripts/.terraform-plan-check.${env.ENVIRONMENT}.yaml"
  - name: SLACK_WEBHOOK_URL
    type: Secret
    required: true
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

      - name: check-terraform-plan
        type: Run
        spec:
          shell: bash
          command: |
            # Make script executable
            chmod +x ./scripts/check-terraform-plan.sh
            
            # Create environment-specific config
            $env:TF_PLAN_CHECK_CONFIG = "./scripts/.terraform-plan-check.yaml"
            
            # Run plan check with environment-specific settings
            if ($env:ENVIRONMENT -eq "production") {
              # In production, fail on any high-risk changes
              ./scripts/check-terraform-plan.sh --fail-on-high-risk -f json tfplan
            } else {
              # In other environments, only fail on critical changes
              ./scripts/check-terraform-plan.sh -f json tfplan
            }
          failure_strategy: FAIL
          environment_variables:
            - name: ENVIRONMENT
              value: ${env.ENVIRONMENT}
            - name: SLACK_WEBHOOK_URL
              value: ${secrets.SLACK_WEBHOOK_URL}
          output_variables:
            - name: PLAN_CHECK_RESULT
              value: ${output.check-terraform-plan}

      - name: notify-plan-changes
        type: Run
        spec:
          shell: PowerShell
          command: |
            $result = Get-Content $env:PLAN_CHECK_RESULT | ConvertFrom-Json
            
            if ($result.critical_changes -gt 0) {
              $message = "🚨 *Critical Changes Detected*`n"
              $message += "Environment: $env:ENVIRONMENT`n"
              $message += "Critical Changes: $($result.critical_changes)`n"
              $message += "High Risk Changes: $($result.high_risk_changes)`n"
              $message += "Total Changes: $($result.total_changes)"
              
              $body = @{
                text = $message
                channel = "#terraform-alerts"
              } | ConvertTo-Json
              
              Invoke-RestMethod -Uri $env:SLACK_WEBHOOK_URL -Method Post -Body $body -ContentType "application/json"
            }
          condition: ${output.check-terraform-plan.critical_changes} > 0

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

### Terraform Plan Check

The `check-terraform-plan.sh` script analyzes Terraform plan files for high-risk changes that could potentially cause issues or outages. The script checks for:

1. **Resource Deletions**
   - Critical resources (DynamoDB tables, RDS clusters, S3 buckets)
   - Other resource deletions

2. **Security Group Changes**
   - Inbound rule modifications
   - Security group deletions

3. **IAM Changes**
   - Role policy modifications
   - IAM policy changes
   - Permission changes

4. **Database Changes**
   - Instance type modifications
   - Configuration changes
   - Parameter group changes

5. **VPC Changes**
   - VPC configuration modifications
   - Subnet changes
   - Route table changes

6. **KMS Key Changes**
   - Key policy modifications
   - Key deletion attempts

The script provides three levels of risk assessment:
- **Critical Changes**: Will fail the pipeline (exit code 1)
- **High-Risk Changes**: Will warn but allow pipeline to continue (exit code 2)
- **Safe Changes**: Will pass the check (exit code 0)

Example output:
```
=== Analyzing Terraform Plan ===

=== Checking for Resource Deletions ===
WARNING: Found resource deletions:
CRITICAL: Attempting to delete aws_dynamodb_table.audit_events

=== Checking Security Group Changes ===
CRITICAL: Modifying inbound rules for aws_security_group.audit_system

=== Checking IAM Changes ===
WARNING: Found IAM changes:
CRITICAL: Modifying IAM permissions: aws_iam_role_policy.audit_system

=== Change Summary ===
Total changes: 15
High-risk changes: 2
Critical changes: 3

ERROR: Critical changes detected. Manual review required.
```

## Implementation Steps

### 1. Harness Pipeline Setup

#### Pipeline Variables
```yaml
variables:
  - name: ENVIRONMENT
    type: String
    required: true
    allowedValues: ["develop", "staging", "production"]
  - name: AWS_REGION
    type: String
    defaultValue: "us-east-1"
  - name: TFC_ORG
    type: String
    required: true
  - name: TFC_WORKSPACE
    type: String
    required: true
  - name: SLACK_WEBHOOK_URL
    type: Secret
    required: true
  - name: WIZ_API_TOKEN
    type: Secret
    required: true
  - name: SEEKER_API_TOKEN
    type: Secret
    required: true
  - name: JMETER_TEST_FILE
    type: String
    defaultValue: "load-test.jmx"
```

#### Pipeline Stages
```yaml
stages:
  - name: setup
    type: CI
    steps:
      - name: setup-aws-credentials
        type: Run
        spec:
          shell: bash
          command: |
            # Configure AWS credentials
            aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
            aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
            aws configure set region $AWS_REGION
            
            # Verify AWS credentials
            aws sts get-caller-identity

      - name: setup-terraform-cloud
        type: Run
        spec:
          shell: bash
          command: |
            # Generate TFC token
            TFC_TOKEN=$(curl -s -X POST \
              -H "Content-Type: application/vnd.api+json" \
              -H "Authorization: Bearer $TFC_API_TOKEN" \
              -d '{"data":{"type":"authentication-tokens","attributes":{"description":"CI/CD Pipeline"}}}' \
              https://app.terraform.io/api/v2/users/me/authentication-tokens \
              | jq -r '.data.attributes.token')
            
            # Configure Terraform Cloud
            cat > ~/.terraformrc <<EOF
            credentials "app.terraform.io" {
              token = "$TFC_TOKEN"
            }
            EOF
            
            # Initialize Terraform
            terraform init

  - name: validate
    type: CI
    steps:
      - name: terraform-validate
        type: Run
        spec:
          shell: bash
          command: |
            terraform validate
            terraform plan -out=tfplan

      - name: wiz-scan
        type: Run
        spec:
          shell: bash
          command: |
            # Run Wiz scan on Terraform plan
            wiz-cli scan --project audit-system \
              --iac-file tfplan \
              --output json > wiz-report.json
            
            # Parse and validate results
            CRITICAL_ISSUES=$(jq -r '.issues[] | select(.severity == "critical") | .title' wiz-report.json)
            if [ ! -z "$CRITICAL_ISSUES" ]; then
              echo "Critical security issues found:"
              echo "$CRITICAL_ISSUES"
              exit 1
            fi

      - name: check-terraform-plan
        type: Run
        spec:
          shell: bash
          command: |
            # Make script executable
            chmod +x ./scripts/check-terraform-plan.sh
            
            # Run plan check with environment-specific settings
            if [ "$ENVIRONMENT" = "production" ]; then
              ./scripts/check-terraform-plan.sh --fail-on-high-risk -f json tfplan
            else
              ./scripts/check-terraform-plan.sh -f json tfplan
            fi
          failure_strategy: FAIL
          environment_variables:
            - name: ENVIRONMENT
              value: ${env.ENVIRONMENT}
            - name: SLACK_WEBHOOK_URL
              value: ${secrets.SLACK_WEBHOOK_URL}
          output_variables:
            - name: PLAN_CHECK_RESULT
              value: ${output.check-terraform-plan}

      - name: notify-plan-changes
        type: Run
        spec:
          shell: bash
          command: |
            # Parse JSON output
            CRITICAL_CHANGES=$(echo $PLAN_CHECK_RESULT | jq -r '.critical_changes')
            HIGH_RISK_CHANGES=$(echo $PLAN_CHECK_RESULT | jq -r '.high_risk_changes')
            
            if [ "$CRITICAL_CHANGES" -gt 0 ]; then
              # Send Slack notification
              curl -X POST -H 'Content-type: application/json' \
                --data "{
                  \"text\": \"🚨 *Critical Changes Detected*\nEnvironment: $ENVIRONMENT\nCritical Changes: $CRITICAL_CHANGES\nHigh Risk Changes: $HIGH_RISK_CHANGES\"
                }" \
                $SLACK_WEBHOOK_URL
            fi
          condition: ${output.check-terraform-plan.critical_changes} > 0

  - name: approval
    type: Approval
    spec:
      timeout: 24h
      approvers:
        - type: User
          users: ["devops-lead", "security-lead"]
        - type: UserGroup
          userGroups: ["infrastructure-team"]
      message: "Please review the Terraform plan changes and security scan results."

  - name: deploy
    type: CD
    steps:
      - name: terraform-apply
        type: Run
        spec:
          shell: bash
          command: |
            terraform apply -auto-approve tfplan

      - name: seeker-scan
        type: Run
        spec:
          shell: bash
          command: |
            # Run Seeker scan
            seeker-cli scan --project audit-system \
              --output json > seeker-report.json
            
            # Parse and validate results
            CRITICAL_ISSUES=$(jq -r '.issues[] | select(.severity == "critical") | .title' seeker-report.json)
            if [ ! -z "$CRITICAL_ISSUES" ]; then
              echo "Critical security issues found:"
              echo "$CRITICAL_ISSUES"
              exit 1
            fi

      - name: load-test
        type: Run
        spec:
          shell: bash
          command: |
            # Run JMeter load test
            jmeter -n -t $JMETER_TEST_FILE -l results.jtl
            
            # Parse results
            ERROR_RATE=$(grep "summary =" results.jtl | awk '{print $7}' | tr -d '%')
            if (( $(echo "$ERROR_RATE > 1" | bc -l) )); then
              echo "Error rate too high: $ERROR_RATE%"
              exit 1
            fi

      - name: verify-deployment
        type: Run
        spec:
          shell: bash
          command: |
            # Check system availability
            MAX_RETRIES=30
            RETRY_INTERVAL=10
            
            for i in $(seq 1 $MAX_RETRIES); do
              if curl -s -f "https://${ENVIRONMENT}.audit-system.example.com/health" > /dev/null; then
                echo "System is available"
                exit 0
              fi
              echo "Attempt $i: System not available yet, waiting..."
              sleep $RETRY_INTERVAL
            done
            
            echo "System failed to become available after $MAX_RETRIES attempts"
            exit 1

      - name: notify-deployment
        type: Run
        spec:
          shell: bash
          command: |
            # Send deployment notification
            curl -X POST -H 'Content-type: application/json' \
              --data "{
                \"text\": \"✅ *Deployment Successful*\nEnvironment: $ENVIRONMENT\nVersion: $VERSION\"
              }" \
              $SLACK_WEBHOOK_URL
```

### 2. Required Scripts

#### Load Test Script (load-test.jmx)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="Audit System Load Test">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments">
        <collectionProp name="Arguments.arguments">
          <elementProp name="host" elementType="Argument">
            <stringProp name="Argument.name">host</stringProp>
            <stringProp name="Argument.value">${ENVIRONMENT}.audit-system.example.com</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Audit Events">
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <stringProp name="LoopController.loops">100</stringProp>
        </elementProp>
        <stringProp name="ThreadGroup.num_threads">50</stringProp>
        <stringProp name="ThreadGroup.ramp_time">10</stringProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.duration">300</stringProp>
        <stringProp name="ThreadGroup.delay">0</stringProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="Create Audit Event">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">{"event_type":"test","user_id":"test-user","timestamp":"2024-01-01T00:00:00Z"}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.path">/api/v1/events</stringProp>
          <stringProp name="HTTPSampler.method">POST</stringProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
          <stringProp name="HTTPSampler.protocol">https</stringProp>
          <stringProp name="HTTPSampler.contentEncoding">UTF-8</stringProp>
          <stringProp name="HTTPSampler.domain">${host}</stringProp>
        </HTTPSamplerProxy>
        <hashTree/>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
```

### 3. Environment Configuration

#### Production Environment
```yaml
# project/scripts/.terraform-plan-check.prod.yaml
output_format: json
fail_on_high_risk: true
verbose: true

resource_classifications:
  critical:
    - aws_dynamodb_table
    - aws_rds_cluster
    - aws_s3_bucket
    - aws_kms_key
    - aws_vpc
    - aws_route53_zone
  high_risk:
    - aws_security_group
    - aws_iam_role
    - aws_iam_policy
    - aws_db_instance

thresholds:
  critical_changes: 0
  high_risk_changes: 1

notifications:
  slack:
    enabled: true
    channel: "#prod-terraform-alerts"
```

#### Staging Environment
```yaml
# project/scripts/.terraform-plan-check.staging.yaml
output_format: json
fail_on_high_risk: false
verbose: true

resource_classifications:
  critical:
    - aws_dynamodb_table
    - aws_rds_cluster
    - aws_s3_bucket
  high_risk:
    - aws_security_group
    - aws_iam_role
    - aws_iam_policy

thresholds:
  critical_changes: 0
  high_risk_changes: 3

notifications:
  slack:
    enabled: true
    channel: "#staging-terraform-alerts"
```

### 4. Monitoring and Alerts

#### Pipeline Metrics
```yaml
metrics:
  - name: deployment_success_rate
    type: gauge
    labels:
      - environment
      - version
  - name: security_scan_score
    type: gauge
    labels:
      - environment
      - scanner
  - name: load_test_performance
    type: gauge
    labels:
      - environment
      - test_name
```

#### Alert Configuration
```yaml
alerts:
  - name: deployment_failure
    condition: deployment_success_rate < 0.95
    severity: critical
    channels:
      - slack: "#pipeline-alerts"
  - name: security_scan_failure
    condition: security_scan_score < 80
    severity: high
    channels:
      - slack: "#security-alerts"
  - name: performance_degradation
    condition: load_test_performance > 1000
    severity: high
    channels:
      - slack: "#performance-alerts"
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

### Terraform Plan Check Integration

The Terraform plan check script can be integrated into the Harness pipeline to enforce infrastructure change policies. Here's how to configure it:

#### 1. Pipeline Step Configuration

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

      - name: check-terraform-plan
        type: Run
        spec:
          shell: bash
          command: |
            # Make script executable
            chmod +x ./scripts/check-terraform-plan.sh
            
            # Create environment-specific config
            $env:TF_PLAN_CHECK_CONFIG = "./scripts/.terraform-plan-check.yaml"
            
            # Run plan check with environment-specific settings
            if ($env:ENVIRONMENT -eq "production") {
              # In production, fail on any high-risk changes
              ./scripts/check-terraform-plan.sh --fail-on-high-risk -f json tfplan
            } else {
              # In other environments, only fail on critical changes
              ./scripts/check-terraform-plan.sh -f json tfplan
            }
          failure_strategy: FAIL
          environment_variables:
            - name: ENVIRONMENT
              value: ${env.ENVIRONMENT}
            - name: SLACK_WEBHOOK_URL
              value: ${secrets.SLACK_WEBHOOK_URL}
          output_variables:
            - name: PLAN_CHECK_RESULT
              value: ${output.check-terraform-plan}

      - name: notify-plan-changes
        type: Run
        spec:
          shell: PowerShell
          command: |
            $result = Get-Content $env:PLAN_CHECK_RESULT | ConvertFrom-Json
            
            if ($result.critical_changes -gt 0) {
              $message = "🚨 *Critical Changes Detected*`n"
              $message += "Environment: $env:ENVIRONMENT`n"
              $message += "Critical Changes: $($result.critical_changes)`n"
              $message += "High Risk Changes: $($result.high_risk_changes)`n"
              $message += "Total Changes: $($result.total_changes)"
              
              $body = @{
                text = $message
                channel = "#terraform-alerts"
              } | ConvertTo-Json
              
              Invoke-RestMethod -Uri $env:SLACK_WEBHOOK_URL -Method Post -Body $body -ContentType "application/json"
            }
          condition: ${output.check-terraform-plan.critical_changes} > 0
```

#### 2. Environment-Specific Configuration

Create environment-specific configuration files:

```yaml
# project/scripts/.terraform-plan-check.prod.yaml
output_format: json
fail_on_high_risk: true
verbose: true

resource_classifications:
  critical:
    - aws_dynamodb_table
    - aws_rds_cluster
    - aws_s3_bucket
    - aws_kms_key
    - aws_vpc
    - aws_route53_zone
  high_risk:
    - aws_security_group
    - aws_iam_role
    - aws_iam_policy
    - aws_db_instance

thresholds:
  critical_changes: 0
  high_risk_changes: 1  # Fail on any high-risk changes in production

notifications:
  slack:
    enabled: true
    channel: "#prod-terraform-alerts"
```

```yaml
# project/scripts/.terraform-plan-check.staging.yaml
output_format: json
fail_on_high_risk: false
verbose: true

resource_classifications:
  critical:
    - aws_dynamodb_table
    - aws_rds_cluster
    - aws_s3_bucket
  high_risk:
    - aws_security_group
    - aws_iam_role
    - aws_iam_policy

thresholds:
  critical_changes: 0
  high_risk_changes: 3  # Allow up to 3 high-risk changes in staging

notifications:
  slack:
    enabled: true
    channel: "#staging-terraform-alerts"
```

#### 3. Pipeline Variables

Add these variables to your Harness pipeline:

```yaml
variables:
  - name: ENVIRONMENT
    type: String
    required: true
    allowedValues: ["develop", "staging", "production"]
  - name: TF_PLAN_CHECK_CONFIG
    type: String
    defaultValue: "./scripts/.terraform-plan-check.${env.ENVIRONMENT}.yaml"
  - name: SLACK_WEBHOOK_URL
    type: Secret
    required: true
```

#### 4. Failure Conditions

The script will fail the pipeline under these conditions:

1. **Production Environment**:
   - Any critical changes (exit code 1)
   - Any high-risk changes (exit code 2)

2. **Staging Environment**:
   - Any critical changes (exit code 1)
   - More than 3 high-risk changes (exit code 2)

3. **Development Environment**:
   - Any critical changes (exit code 1)
   - No failure on high-risk changes

#### 5. Output Handling

The script outputs JSON that can be used in subsequent steps:

```json
{
  "total_changes": 15,
  "high_risk_changes": 2,
  "critical_changes": 1,
  "status": "critical"
}
```

This output can be used to:
- Trigger notifications
- Update deployment status
- Generate reports
- Control pipeline flow

#### 6. Best Practices

1. **Environment-Specific Rules**:
   - Stricter rules in production
   - More lenient rules in development
   - Custom thresholds per environment

2. **Notification Strategy**:
   - Immediate alerts for critical changes
   - Daily summaries for high-risk changes
   - Different channels per environment

3. **Monitoring and Metrics**:
   - Track change patterns over time
   - Monitor failure rates
   - Analyze common high-risk changes

4. **Documentation**:
   - Document all critical resources
   - Maintain change history
   - Update thresholds based on team feedback 
```

## Pipeline Resilience and Auto-Healing

### 1. Pipeline Resilience Mechanisms

#### Retry and Backoff Strategy
```yaml
resilience:
  retry_strategy:
    max_attempts: 3
    initial_delay: 10
    max_delay: 60
    backoff_factor: 2
    jitter: true

  steps:
    - name: terraform-apply
      retry_on:
        - "Error: timeout"
        - "Error: rate limit exceeded"
        - "Error: connection refused"
      auto_heal:
        - action: "terraform refresh"
          condition: "state mismatch"
        - action: "terraform init -reconfigure"
          condition: "backend error"

    - name: load-test
      retry_on:
        - "Error: connection timeout"
        - "Error: too many connections"
      auto_heal:
        - action: "scale_up_resources"
          condition: "resource exhaustion"
        - action: "clear_connections"
          condition: "connection pool full"
```

#### Circuit Breaker Pattern
```yaml
circuit_breaker:
  failure_threshold: 3
  reset_timeout: 300
  half_open_timeout: 60
  monitor:
    - metric: "deployment_success_rate"
      threshold: 0.95
    - metric: "error_rate"
      threshold: 0.05
```

### 2. Auto-Correction Mechanisms

#### State Recovery
```yaml
state_recovery:
  terraform:
    - name: "state_lock_recovery"
      trigger: "state lock timeout"
      actions:
        - "terraform force-unlock"
        - "terraform refresh"
    
    - name: "state_conflict_resolution"
      trigger: "state conflict"
      actions:
        - "terraform state pull"
        - "terraform state push"
        - "terraform refresh"

  deployment:
    - name: "rollback_on_failure"
      trigger: "deployment failure"
      actions:
        - "terraform state list"
        - "terraform destroy -target"
        - "terraform apply previous_state"
```

#### Resource Health Checks
```yaml
health_checks:
  pre_deployment:
    - name: "resource_availability"
      check: "aws health describe-events"
      threshold: 0.95
      action: "wait_and_retry"
    
    - name: "capacity_check"
      check: "aws service-quotas get-service-quota"
      threshold: 0.8
      action: "request_quota_increase"

  post_deployment:
    - name: "service_health"
      check: "curl -f https://${ENVIRONMENT}.audit-system.example.com/health"
      retries: 5
      interval: 30
      action: "rollback_on_failure"
```

### 3. Auto-Healing Implementation

#### Pipeline Stage Enhancements
```yaml
stages:
  - name: validate
    type: CI
    steps:
      - name: terraform-validate
        type: Run
        spec:
          shell: bash
          command: |
            # Auto-healing validation
            function validate_with_healing() {
              local max_attempts=3
              local attempt=1
              
              while [ $attempt -le $max_attempts ]; do
                if terraform validate; then
                  return 0
                fi
                
                # Auto-healing actions
                case $? in
                  1) # Syntax error
                    terraform fmt
                    ;;
                  2) # State error
                    terraform init -reconfigure
                    ;;
                  3) # Provider error
                    terraform init -upgrade
                    ;;
                esac
                
                attempt=$((attempt + 1))
                sleep $((attempt * 10))
              done
              
              return 1
            }
            
            validate_with_healing

      - name: check-terraform-plan
        type: Run
        spec:
          shell: bash
          command: |
            # Auto-healing plan check
            function check_plan_with_healing() {
              local result
              result=$(./scripts/check-terraform-plan.sh -f json tfplan)
              
              if [ $? -eq 0 ]; then
                echo "$result"
                return 0
              fi
              
              # Auto-healing actions based on check results
              local critical_changes=$(echo "$result" | jq -r '.critical_changes')
              local high_risk_changes=$(echo "$result" | jq -r '.high_risk_changes')
              
              if [ "$critical_changes" -gt 0 ]; then
                # Attempt to fix critical changes
                ./scripts/auto-fix-critical-changes.sh
              elif [ "$high_risk_changes" -gt 0 ]; then
                # Attempt to fix high-risk changes
                ./scripts/auto-fix-high-risk-changes.sh
              fi
              
              # Re-run check after fixes
              ./scripts/check-terraform-plan.sh -f json tfplan
            }
            
            check_plan_with_healing

  - name: deploy
    type: CD
    steps:
      - name: terraform-apply
        type: Run
        spec:
          shell: bash
          command: |
            # Auto-healing deployment
            function deploy_with_healing() {
              local max_attempts=3
              local attempt=1
              
              while [ $attempt -le $max_attempts ]; do
                if terraform apply -auto-approve tfplan; then
                  return 0
                fi
                
                # Auto-healing actions
                case $? in
                  1) # State error
                    terraform refresh
                    ;;
                  2) # Resource error
                    ./scripts/cleanup-failed-resources.sh
                    ;;
                  3) # Provider error
                    terraform init -upgrade
                    ;;
                esac
                
                attempt=$((attempt + 1))
                sleep $((attempt * 30))
              done
              
              return 1
            }
            
            deploy_with_healing

      - name: verify-deployment
        type: Run
        spec:
          shell: bash
          command: |
            # Auto-healing verification
            function verify_with_healing() {
              local max_retries=30
              local retry_interval=10
              local attempt=1
              
              while [ $attempt -le $max_retries ]; do
                if curl -s -f "https://${ENVIRONMENT}.audit-system.example.com/health" > /dev/null; then
                  return 0
                fi
                
                # Auto-healing actions
                if [ $attempt -eq 10 ]; then
                  # Restart services after 10 failed attempts
                  ./scripts/restart-services.sh
                elif [ $attempt -eq 20 ]; then
                  # Scale up resources after 20 failed attempts
                  ./scripts/scale-up-resources.sh
                fi
                
                attempt=$((attempt + 1))
                sleep $retry_interval
              done
              
              return 1
            }
            
            verify_with_healing
```

### 4. Monitoring and Auto-Healing Triggers

#### Health Monitoring
```yaml
monitoring:
  metrics:
    - name: "pipeline_success_rate"
      type: "gauge"
      threshold: 0.95
      action: "alert_and_analyze"
    
    - name: "deployment_duration"
      type: "histogram"
      threshold: 300
      action: "optimize_pipeline"
    
    - name: "error_rate"
      type: "gauge"
      threshold: 0.05
      action: "auto_heal"

  alerts:
    - name: "pipeline_degradation"
      condition: "pipeline_success_rate < 0.95"
      actions:
        - "analyze_failures"
        - "notify_team"
        - "trigger_auto_heal"
    
    - name: "resource_exhaustion"
      condition: "resource_usage > 0.9"
      actions:
        - "scale_resources"
        - "cleanup_unused"
        - "notify_team"
```

#### Auto-Healing Triggers
```yaml
auto_healing:
  triggers:
    - name: "state_conflict"
      condition: "terraform state conflict"
      actions:
        - "resolve_state_conflict"
        - "notify_team"
    
    - name: "resource_failure"
      condition: "resource creation failure"
      actions:
        - "cleanup_failed_resources"
        - "retry_deployment"
        - "notify_team"
    
    - name: "performance_degradation"
      condition: "response_time > threshold"
      actions:
        - "scale_resources"
        - "optimize_configuration"
        - "notify_team"
```

### 5. Best Practices for Pipeline Resilience

1. **State Management**:
   - Implement state locking
   - Regular state backups
   - State conflict resolution
   - State drift detection

2. **Resource Management**:
   - Resource cleanup on failure
   - Resource health monitoring
   - Automatic scaling
   - Resource quota management

3. **Error Handling**:
   - Comprehensive error logging
   - Error pattern recognition
   - Automatic error recovery
   - Error notification system

4. **Performance Optimization**:
   - Parallel execution where possible
   - Resource usage optimization
   - Caching mechanisms
   - Performance monitoring

5. **Security**:
   - Credential rotation
   - Access control
   - Audit logging
   - Security scanning

6. **Monitoring and Alerting**:
   - Real-time monitoring
   - Proactive alerting
   - Performance metrics
   - Health checks

7. **Documentation**:
   - Change history
   - Recovery procedures
   - Configuration management
   - Troubleshooting guides
