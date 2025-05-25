module "monitoring" {
  source = "./modules/monitoring"

  environment         = var.environment
  aws_region         = var.aws_region
  dynamodb_table_name = module.api.dynamodb_table_name
} 