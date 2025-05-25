# Dev Environment Configuration

provider "aws" {
  region = var.aws_region
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = var.tags
}

# API Module
module "api" {
  source = "../../modules/api"

  environment            = var.environment
  stage_name            = var.api_stage_name
  lambda_zip_path       = var.lambda_zip_path
  private_subnet_ids    = module.networking.private_subnet_ids
  lambda_security_group_id = module.networking.lambda_security_group_id
  tags                  = var.tags
}

# Frontend Module
module "frontend" {
  source = "../../modules/frontend"

  environment      = var.environment
  domain_name      = var.domain_name
  hosted_zone_id   = var.hosted_zone_id
  certificate_arn  = var.certificate_arn
  tags             = var.tags
}

module "audit_system" {
  source = "../../modules"

  environment = "dev"
  aws_region = "us-east-1"

  # VPC Configuration
  vpc_cidr = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

  # DynamoDB Configuration
  dynamodb_read_capacity = 5
  dynamodb_write_capacity = 5
  dynamodb_ttl_days = 365

  # Lambda Configuration
  lambda_memory_size = 256
  lambda_timeout = 30

  # API Gateway Configuration
  api_stage_name = "dev"
  enable_api_logging = true
  api_log_level = "INFO"

  # Monitoring Configuration
  enable_cloudwatch_alarms = true
  alarm_email = "dev-alerts@example.com"

  tags = {
    Environment = "dev"
    Project     = "audit-system"
    ManagedBy   = "terraform"
  }
} 