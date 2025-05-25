variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for audit events"
  type        = string
  default     = "audit-events"
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue for audit events"
  type        = string
  default     = "audit-events-queue"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "audit-events-processor"
}

variable "lambda_zip_path" {
  description = "Path to the Lambda function deployment package"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Environment = "production"
    Project     = "audit-system"
  }
} 