# Frontend Deployment Script
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

    # Get S3 bucket name from Terraform output
    $s3BucketName = terraform output -raw s3_bucket_name
    Test-CommandStatus "terraform output" "Failed to get S3 bucket name"

    # Build frontend application
    Write-Log "Building frontend application..."
    Set-Location ../src/frontend
    npm install
    Test-CommandStatus "npm install" "Failed to install frontend dependencies"
    
    npm run build
    Test-CommandStatus "npm run build" "Failed to build frontend application"

    # Upload frontend files to S3
    Write-Log "Uploading frontend files to S3..."
    $buildPath = "dist"
    if (-not (Test-Path $buildPath)) {
        throw "Build directory not found: $buildPath"
    }

    # Get all files from build directory
    $files = Get-ChildItem -Path $buildPath -Recurse -File

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($buildPath.Length + 1)
        $s3Key = $relativePath.Replace("\", "/")
        
        # Set content type based on file extension
        $contentType = switch ($file.Extension) {
            ".html" { "text/html" }
            ".css"  { "text/css" }
            ".js"   { "application/javascript" }
            ".json" { "application/json" }
            ".png"  { "image/png" }
            ".jpg"  { "image/jpeg" }
            ".svg"  { "image/svg+xml" }
            default { "application/octet-stream" }
        }

        # Upload file to S3
        Write-S3Object -BucketName $s3BucketName `
            -Key $s3Key `
            -File $file.FullName `
            -ContentType $contentType `
            -CannedACLName "public-read"
    }

    # Invalidate CloudFront cache
    Write-Log "Invalidating CloudFront cache..."
    $cloudfrontDistributionId = terraform output -raw cloudfront_distribution_id
    Test-CommandStatus "terraform output" "Failed to get CloudFront distribution ID"

    New-CFInvalidation -DistributionId $cloudfrontDistributionId `
        -InvalidationBatch @{
            CallerReference = [DateTime]::Now.Ticks.ToString()
            Paths = @{
                Quantity = 1
                Items = @("/*")
            }
        }

    # Run Seeker scan
    Write-Log "Running Seeker security scan..."
    $SEEKER_API_TOKEN = $env:SEEKER_API_TOKEN
    if (-not $SEEKER_API_TOKEN) {
        throw "SEEKER_API_TOKEN environment variable is not set"
    }

    # Get frontend URL from Terraform output
    $frontendUrl = terraform output -raw cloudfront_domain_name
    Test-CommandStatus "terraform output" "Failed to get frontend URL"

    # Run Seeker scan on the frontend
    $seekerScanResult = Invoke-RestMethod -Uri "https://api.seeker.io/v1/scan" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $SEEKER_API_TOKEN"
            "Content-Type" = "application/json"
        } `
        -Body @{
            "target" = $frontendUrl
            "scan_type" = "web"
        } | ConvertTo-Json

    if ($seekerScanResult.status -ne "success") {
        throw "Seeker scan failed: $($seekerScanResult.message)"
    }

    Write-Log "Frontend deployment completed successfully!"
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
    Set-Location ../../scripts/deployment
} 