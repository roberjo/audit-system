module "audit_system" {
  source = "../../modules"

  environment = "staging"
  aws_region = "us-east-1"

  # VPC Configuration
  vpc_cidr = "10.1.0.0/16"
  private_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  public_subnet_cidrs = ["10.1.101.0/24", "10.1.102.0/24"]

  # DynamoDB Configuration
  dynamodb_read_capacity = 10
  dynamodb_write_capacity = 10
  dynamodb_ttl_days = 365

  # Lambda Configuration
  lambda_memory_size = 512
  lambda_timeout = 30

  # API Gateway Configuration
  api_stage_name = "staging"
  enable_api_logging = true
  api_log_level = "INFO"

  # Monitoring Configuration
  enable_cloudwatch_alarms = true
  alarm_email = "staging-alerts@example.com"

  tags = {
    Environment = "staging"
    Project     = "audit-system"
    ManagedBy   = "terraform"
  }
} 