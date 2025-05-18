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