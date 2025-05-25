# API Module
# This module sets up the API Gateway and related resources

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.environment}-api"
  description = "Audit System API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Environment = var.environment
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.stage_name
  deployment_id = aws_api_gateway_deployment.main.id

  variables = {
    environment = var.environment
  }

  tags = {
    Environment = var.environment
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.audit_events,
      aws_api_gateway_method.audit_events,
      aws_api_gateway_integration.audit_events
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Resource
resource "aws_api_gateway_resource" "audit_events" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "events"
}

# API Gateway Method
resource "aws_api_gateway_method" "audit_events" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.audit_events.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "audit_events" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.audit_events.id
  http_method             = aws_api_gateway_method.audit_events.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sns:path//"
  credentials             = aws_iam_role.api_gateway.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=Publish&TopicArn=$util.urlEncode('${aws_sns_topic.audit_events.arn}')&Message=$util.urlEncode($input.body)"
  }
}

# API Gateway Method Response
resource "aws_api_gateway_method_response" "audit_events" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.audit_events.id
  http_method = aws_api_gateway_method.audit_events.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# API Gateway Integration Response
resource "aws_api_gateway_integration_response" "audit_events" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.audit_events.id
  http_method = aws_api_gateway_method.audit_events.http_method
  status_code = aws_api_gateway_method_response.audit_events.status_code

  response_templates = {
    "application/json" = "{\"message\": \"Audit event received successfully\"}"
  }
}

# Lambda Function
resource "aws_lambda_function" "audit_events" {
  filename         = var.lambda_zip_path
  function_name    = "${var.environment}-audit-events"
  role            = aws_iam_role.lambda.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      DYNAMODB_TABLE = aws_dynamodb_table.audit_events.name
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  tags = {
    Environment = var.environment
  }
}

# Lambda Function for Processing Audit Events
resource "aws_lambda_function" "audit_events_processor" {
  filename         = var.lambda_zip_path
  function_name    = "${var.environment}-audit-events-processor"
  role            = aws_iam_role.lambda_processor.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 300
  memory_size     = 1024

  environment {
    variables = {
      ENVIRONMENT = var.environment
      DYNAMODB_TABLE = aws_dynamodb_table.audit_events.name
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  tags = {
    Environment = var.environment
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "audit_events" {
  name           = "${var.environment}-audit-events"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  range_key      = "timestamp"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "systemId"
    type = "S"
  }

  # Single GSI for both user and system queries
  global_secondary_index {
    name            = "AuditIndex"
    hash_key        = "userId"
    range_key       = "timestamp"
    projection_type = "INCLUDE"
    non_key_attributes = [
      "systemId",
      "dataBefore",
      "dataAfter",
      "ttl"
    ]
  }

  # Local Secondary Index for system-based queries
  local_secondary_index {
    name            = "SystemIndex"
    range_key       = "timestamp"
    projection_type = "INCLUDE"
    non_key_attributes = [
      "userId",
      "dataBefore",
      "dataAfter",
      "ttl"
    ]
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = {
    Environment = var.environment
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda" {
  name = "${var.environment}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.audit_events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM Role for Lambda Processor
resource "aws_iam_role" "lambda_processor" {
  name = "${var.environment}-lambda-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda Processor
resource "aws_iam_role_policy" "lambda_processor" {
  name = "${var.environment}-lambda-processor-policy"
  role = aws_iam_role.lambda_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.audit_events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.audit_events.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# SNS Topic for Audit Events
resource "aws_sns_topic" "audit_events" {
  name = "${var.environment}-audit-events"
  
  tags = {
    Environment = var.environment
  }
}

# SQS Queue for Audit Events
resource "aws_sqs_queue" "audit_events" {
  name                       = "${var.environment}-audit-events"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600  # 14 days
  delay_seconds             = 0
  receive_wait_time_seconds = 20  # Enable long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.audit_events_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Environment = var.environment
  }
}

# Dead Letter Queue for Audit Events
resource "aws_sqs_queue" "audit_events_dlq" {
  name = "${var.environment}-audit-events-dlq"
  
  tags = {
    Environment = var.environment
  }
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "audit_events" {
  arn = aws_sns_topic.audit_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.audit_events.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn": aws_api_gateway_rest_api.main.execution_arn
          }
        }
      }
    ]
  })
}

# SNS to SQS Subscription
resource "aws_sns_topic_subscription" "audit_events" {
  topic_arn = aws_sns_topic.audit_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.audit_events.arn
}

# SQS Queue Policy
resource "aws_sqs_queue_policy" "audit_events" {
  queue_url = aws_sqs_queue.audit_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.audit_events.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn": aws_sns_topic.audit_events.arn
          }
        }
      }
    ]
  })
}

# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway" {
  name = "${var.environment}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for API Gateway
resource "aws_iam_role_policy" "api_gateway" {
  name = "${var.environment}-api-gateway-policy"
  role = aws_iam_role.api_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.audit_events.arn
      }
    ]
  })
}

# Lambda Event Source Mapping
resource "aws_lambda_event_source_mapping" "audit_events" {
  event_source_arn = aws_sqs_queue.audit_events.arn
  function_name    = aws_lambda_function.audit_events_processor.arn
  batch_size       = 10
  enabled          = true
}

# Lambda Function for Querying Audit Events
resource "aws_lambda_function" "audit_query" {
  filename         = var.lambda_zip_path
  function_name    = "${var.environment}-audit-query"
  role            = aws_iam_role.lambda_query.arn
  handler         = "AuditQuery::AuditQuery.Function::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      DYNAMODB_TABLE = aws_dynamodb_table.audit_events.name
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  tags = {
    Environment = var.environment
  }
}

# IAM Role for Query Lambda
resource "aws_iam_role" "lambda_query" {
  name = "${var.environment}-lambda-query-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Query Lambda
resource "aws_iam_role_policy" "lambda_query" {
  name = "${var.environment}-lambda-query-policy"
  role = aws_iam_role.lambda_query.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.audit_events.arn,
          "${aws_dynamodb_table.audit_events.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# API Gateway Resource for Query
resource "aws_api_gateway_resource" "audit_query" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "query"
}

# API Gateway Method for Query
resource "aws_api_gateway_method" "audit_query" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.audit_query.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration for Query
resource "aws_api_gateway_integration" "audit_query" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.audit_query.id
  http_method             = aws_api_gateway_method.audit_query.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.audit_query.invoke_arn
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "audit_query" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audit_query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}

# API Gateway Method Response for Query
resource "aws_api_gateway_method_response" "audit_query" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.audit_query.id
  http_method = aws_api_gateway_method.audit_query.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Get current AWS region
data "aws_region" "current" {} 