module "audit_system" {
  source = "../../modules"

  environment = "prod"
  aws_region = "us-east-1"

  # VPC Configuration
  vpc_cidr = "10.2.0.0/16"
  private_subnet_cidrs = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  public_subnet_cidrs = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]

  # DynamoDB Configuration
  dynamodb_read_capacity = 20
  dynamodb_write_capacity = 20
  dynamodb_ttl_days = 365

  # Lambda Configuration
  lambda_memory_size = 1024
  lambda_timeout = 30

  # API Gateway Configuration
  api_stage_name = "prod"
  enable_api_logging = true
  api_log_level = "INFO"

  # Monitoring Configuration
  enable_cloudwatch_alarms = true
  alarm_email = "prod-alerts@example.com"

  tags = {
    Environment = "prod"
    Project     = "audit-system"
    ManagedBy   = "terraform"
  }
} 