# Deployment Guide

## Overview

This guide outlines the deployment process for the Audit System, including infrastructure provisioning, application deployment, and post-deployment verification.

## Prerequisites

### 1. Required Tools
- AWS CLI v2
- Terraform v1.5+
- Node.js v18+
- .NET Core 8 SDK
- Python 3.9+
- HashiCorp Vault CLI
- Git

### 2. AWS Account Setup
- AWS Organizations configured
- Appropriate IAM roles and permissions
- VPC with required subnets
- KMS keys for encryption

### 3. HashiCorp Vault Setup
- Vault server deployed
- Appropriate policies configured
- Secrets engine enabled
- Authentication method configured

## Infrastructure Deployment

### 1. Terraform Configuration

#### Provider Configuration
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
  backend "remote" {
    organization = "audit-system"
    workspaces {
      name = "audit-system-prod"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "audit-system"
    }
  }
}
```

#### VPC Configuration
```hcl
module "vpc" {
  source = "./modules/vpc"

  name             = "audit-system-vpc"
  cidr             = "10.0.0.0/16"
  azs              = ["us-east-1a", "us-east-1b"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = var.environment
  }
}
```

#### Database Configuration
```hcl
module "aurora" {
  source = "./modules/aurora"

  cluster_identifier = "audit-system-aurora"
  engine            = "aurora-postgresql"
  engine_version    = "14.7"
  instance_class    = "db.r6g.large"
  instances         = 2

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnets

  security_group_rules = {
    vpc_ingress = {
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
}
```

### 2. Application Infrastructure

#### Lambda Functions
```hcl
module "lambda" {
  source = "./modules/lambda"

  for_each = {
    "audit-processor" = {
      runtime     = "dotnet8"
      handler     = "AuditSystem.Processor::AuditSystem.Processor.Function::FunctionHandler"
      memory_size = 1024
      timeout     = 300
    }
    "audit-enricher" = {
      runtime     = "python3.9"
      handler     = "app.lambda_handler"
      memory_size = 1024
      timeout     = 300
    }
  }

  name    = each.key
  config  = each.value
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.private_subnets
}
```

#### API Gateway
```hcl
module "api_gateway" {
  source = "./modules/api_gateway"

  name        = "audit-system-api"
  description = "Audit System API Gateway"

  cors_configuration = {
    allow_origins = ["https://audit-system.example.com"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["Content-Type", "Authorization"]
  }

  cognito_user_pool_arn = module.cognito.user_pool_arn
}
```

### 3. Security Configuration

#### KMS Keys
```hcl
module "kms" {
  source = "./modules/kms"

  key_aliases = [
    "audit-system-dynamodb",
    "audit-system-s3",
    "audit-system-aurora"
  ]

  key_administrators = [
    "arn:aws:iam::${var.aws_account_id}:role/Admin"
  ]

  key_users = [
    module.lambda["audit-processor"].role_arn,
    module.lambda["audit-enricher"].role_arn
  ]
}
```

#### Vault Configuration
```hcl
module "vault" {
  source = "./modules/vault"

  path = "audit-system"
  
  policies = {
    "audit-system-read" = {
      capabilities = ["read"]
      path         = "secret/data/audit-system/*"
    }
    "audit-system-write" = {
      capabilities = ["create", "update"]
      path         = "secret/data/audit-system/*"
    }
  }
}
```

## Application Deployment

### 1. Frontend Deployment

#### Build Process
```bash
# Install dependencies
npm install

# Build application
npm run build

# Deploy to S3
aws s3 sync dist/ s3://audit-system-frontend-${ENVIRONMENT}/
```

#### CloudFront Distribution
```hcl
module "cloudfront" {
  source = "./modules/cloudfront"

  domain_name     = "audit-system.example.com"
  s3_bucket_name  = "audit-system-frontend-${var.environment}"
  certificate_arn = module.acm.certificate_arn

  aliases = ["audit-system.${var.environment}.example.com"]
}
```

### 2. Backend Deployment

#### Lambda Deployment
```bash
# .NET Lambda
dotnet publish -c Release
cd bin/Release/net8.0/publish
zip -r function.zip .
aws lambda update-function-code --function-name audit-processor --zip-file fileb://function.zip

# Python Lambda
pip install -r requirements.txt -t .
zip -r function.zip .
aws lambda update-function-code --function-name audit-enricher --zip-file fileb://function.zip
```

#### Database Migrations
```bash
# Run migrations
dotnet ef database update --project AuditSystem.Infrastructure --startup-project AuditSystem.API
```

## Deployment Process

### 1. Infrastructure Deployment
```bash
# Initialize Terraform
terraform init

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan
```

### 2. Application Deployment
```bash
# Deploy frontend
./scripts/deploy-frontend.sh

# Deploy backend
./scripts/deploy-backend.sh

# Run migrations
./scripts/run-migrations.sh
```

### 3. Post-Deployment Verification

#### Health Checks
```bash
# API Health Check
curl https://api.audit-system.${ENVIRONMENT}.example.com/health

# Frontend Health Check
curl https://audit-system.${ENVIRONMENT}.example.com/health
```

#### Smoke Tests
```bash
# Run smoke tests
npm run test:smoke
```

## Monitoring Setup

### 1. CloudWatch Dashboards
```hcl
module "cloudwatch" {
  source = "./modules/cloudwatch"

  dashboard_name = "audit-system-${var.environment}"

  metrics = {
    "LambdaInvocations" = {
      namespace = "AWS/Lambda"
      metric_name = "Invocations"
      dimensions = {
        FunctionName = module.lambda["audit-processor"].function_name
      }
    }
    "APILatency" = {
      namespace = "AWS/ApiGateway"
      metric_name = "Latency"
      dimensions = {
        ApiName = module.api_gateway.name
      }
    }
  }
}
```

### 2. Alarms
```hcl
module "alarms" {
  source = "./modules/alarms"

  environment = var.environment

  alarms = {
    "HighErrorRate" = {
      metric_name = "ErrorCount"
      threshold   = 10
      period      = 300
    }
    "HighLatency" = {
      metric_name = "Latency"
      threshold   = 1000
      period      = 300
    }
  }
}
```

## Rollback Procedures

### 1. Infrastructure Rollback
```bash
# Revert Terraform state
terraform apply -auto-approve -var-file=previous.tfvars
```

### 2. Application Rollback
```bash
# Revert Lambda functions
aws lambda update-function-code --function-name audit-processor --zip-file fileb://previous.zip

# Revert frontend
aws s3 sync s3://audit-system-frontend-${ENVIRONMENT}-backup/ s3://audit-system-frontend-${ENVIRONMENT}/
```

### 3. Database Rollback
```bash
# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier audit-system-aurora \
  --db-snapshot-identifier audit-system-snapshot-${TIMESTAMP}
```

## Maintenance Procedures

### 1. Regular Maintenance
- Weekly security updates
- Monthly dependency updates
- Quarterly performance reviews
- Annual architecture review

### 2. Backup Procedures
- Daily DynamoDB backups
- Continuous Aurora backups
- Weekly S3 bucket backups
- Monthly full system backup

### 3. Monitoring and Alerts
- Daily log review
- Weekly metric analysis
- Monthly capacity planning
- Quarterly performance optimization 