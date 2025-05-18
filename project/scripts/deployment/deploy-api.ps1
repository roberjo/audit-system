# API Deployment Script
param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [string]$Region,
    
    [Parameter(Mandatory=$true)]
    [string]$TerraformWorkspace
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to log messages
function Write-Log {
    param($Message)
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

# Function to check command status
function Test-CommandStatus {
    param($Command, $ErrorMessage)
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Error: $ErrorMessage"
        exit 1
    }
}

try {
    # Initialize Terraform
    Write-Log "Initializing Terraform..."
    terraform init
    Test-CommandStatus "terraform init" "Failed to initialize Terraform"

    # Select Terraform workspace
    Write-Log "Selecting Terraform workspace: $TerraformWorkspace"
    terraform workspace select $TerraformWorkspace
    Test-CommandStatus "terraform workspace select" "Failed to select Terraform workspace"

    # Plan Terraform changes
    Write-Log "Planning Terraform changes..."
    terraform plan -var-file="config/terraform.tfvars.$Environment" -out=tfplan
    Test-CommandStatus "terraform plan" "Failed to plan Terraform changes"

    # Run Wiz scan on tfplan
    Write-Log "Running Wiz security scan..."
    $WIZ_API_TOKEN = $env:WIZ_API_TOKEN
    if (-not $WIZ_API_TOKEN) {
        throw "WIZ_API_TOKEN environment variable is not set"
    }
    
    # Convert tfplan to JSON for Wiz scan
    terraform show -json tfplan > tfplan.json
    Test-CommandStatus "terraform show" "Failed to convert tfplan to JSON"

    # Run Wiz scan
    $wizScanResult = Invoke-RestMethod -Uri "https://api.wiz.io/v1/scan" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $WIZ_API_TOKEN"
            "Content-Type" = "application/json"
        } `
        -Body (Get-Content -Raw tfplan.json)

    if ($wizScanResult.status -ne "success") {
        throw "Wiz scan failed: $($wizScanResult.message)"
    }

    # Check for critical issues
    if ($wizScanResult.critical_issues -gt 0) {
        throw "Critical security issues found in the plan. Please review the Wiz scan results."
    }

    # Apply Terraform changes
    Write-Log "Applying Terraform changes..."
    terraform apply -auto-approve tfplan
    Test-CommandStatus "terraform apply" "Failed to apply Terraform changes"

    # Run Seeker scan
    Write-Log "Running Seeker security scan..."
    $SEEKER_API_TOKEN = $env:SEEKER_API_TOKEN
    if (-not $SEEKER_API_TOKEN) {
        throw "SEEKER_API_TOKEN environment variable is not set"
    }

    # Get API endpoint from Terraform output
    $apiEndpoint = terraform output -raw api_endpoint
    Test-CommandStatus "terraform output" "Failed to get API endpoint"

    # Run Seeker scan on the API
    $seekerScanResult = Invoke-RestMethod -Uri "https://api.seeker.io/v1/scan" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $SEEKER_API_TOKEN"
            "Content-Type" = "application/json"
        } `
        -Body @{
            "target" = $apiEndpoint
            "scan_type" = "api"
        } | ConvertTo-Json

    if ($seekerScanResult.status -ne "success") {
        throw "Seeker scan failed: $($seekerScanResult.message)"
    }

    # Run JMeter load test
    Write-Log "Running JMeter load test..."
    $JMETER_TEST_FILE = $env:JMETER_TEST_FILE
    if (-not $JMETER_TEST_FILE) {
        throw "JMETER_TEST_FILE environment variable is not set"
    }

    jmeter -n -t $JMETER_TEST_FILE -l results.jtl
    Test-CommandStatus "jmeter" "Failed to run JMeter load test"

    # Check system availability
    Write-Log "Checking system availability..."
    $healthCheckResult = Invoke-RestMethod -Uri "$apiEndpoint/health" -Method Get
    if ($healthCheckResult.status -ne "healthy") {
        throw "System health check failed: $($healthCheckResult.message)"
    }

    Write-Log "API deployment completed successfully!"
} catch {
    Write-Log "Error: $_"
    exit 1
} finally {
    # Cleanup
    if (Test-Path tfplan) {
        Remove-Item tfplan
    }
    if (Test-Path tfplan.json) {
        Remove-Item tfplan.json
    }
    if (Test-Path results.jtl) {
        Remove-Item results.jtl
    }
} 