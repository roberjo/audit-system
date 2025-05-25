terraform {
  backend "s3" {
    bucket         = "audit-system-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "audit-system-terraform-locks"
    encrypt        = true
  }
} 