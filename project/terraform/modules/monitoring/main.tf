# CloudWatch Dashboard for Audit System
resource "aws_cloudwatch_dashboard" "audit_system" {
  dashboard_name = "audit-system-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AuditSystem", "QueryExecutionTime", "Environment", var.environment],
            ["AuditSystem", "QueryExecutionTime", "Environment", var.environment, { stat = "p95" }],
            ["AuditSystem", "QueryExecutionTime", "Environment", var.environment, { stat = "p99" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Query Execution Time"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AuditSystem", "QueryResultCount", "Environment", var.environment]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Total Query Results"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AuditSystem", "QuerySuccess", "Environment", var.environment]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Successful Queries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_table_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "DynamoDB Capacity Units"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_function_name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Performance"
        }
      }
    ]
  })
}

# CloudWatch Alarms for DynamoDB
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttled_requests" {
  alarm_name          = "${var.environment}-dynamodb-throttled-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "10"
  alarm_description  = "This alarm monitors for throttled requests in DynamoDB"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  alarm_name          = "${var.environment}-dynamodb-system-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "This alarm monitors for system errors in DynamoDB"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_user_errors" {
  alarm_name          = "${var.environment}-dynamodb-user-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "This alarm monitors for user errors in DynamoDB"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "audit-system-alerts-${var.environment}"
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# CloudWatch Log Group for Custom Metrics
resource "aws_cloudwatch_log_group" "audit_metrics" {
  name              = "/aws/audit-system/metrics"
  retention_in_days = 30
}

# CloudWatch Log Metric Filter for Query Performance
resource "aws_cloudwatch_log_metric_filter" "slow_queries" {
  name           = "${var.environment}-slow-queries"
  pattern        = "{ $.duration > 1000 }"
  log_group_name = aws_cloudwatch_log_group.audit_metrics.name

  metric_transformation {
    name          = "SlowQueries"
    namespace     = "AuditSystem/DynamoDB"
    value         = "1"
    default_value = "0"
  }
}

# CloudWatch Alarm for Slow Queries
resource "aws_cloudwatch_metric_alarm" "slow_queries" {
  alarm_name          = "${var.environment}-slow-queries"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SlowQueries"
  namespace           = "AuditSystem/DynamoDB"
  period             = "300"
  statistic          = "Sum"
  threshold          = "5"
  alarm_description  = "This alarm monitors for slow queries in DynamoDB"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "audit-system-high-error-rate-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "QuerySuccess"
  namespace           = "AuditSystem"
  period             = 300
  statistic          = "Sum"
  threshold          = 10
  alarm_description  = "This metric monitors the number of failed queries"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "audit-system-high-latency-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "QueryExecutionTime"
  namespace           = "AuditSystem"
  period             = 300
  statistic          = "p95"
  threshold          = 1000
  alarm_description  = "This metric monitors query execution time"
  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
} 