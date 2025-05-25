# Audit Query Lambda Function

## Overview

This Lambda function provides a query interface for the audit system, allowing retrieval of audit records from DynamoDB based on various criteria. It's built using .NET Core 8 and integrates with AWS API Gateway.

## Features

- Query by user ID
- Query by system ID
- Combined user and system ID queries
- Date range filtering
- Pagination support
- Error handling and logging
- CloudWatch integration

## Prerequisites

- .NET Core 8 SDK
- AWS CLI configured with appropriate credentials
- Terraform for infrastructure deployment

## Project Structure

```
audit-query/
├── Program.cs           # Main Lambda function code
├── AuditQuery.csproj    # Project file with dependencies
└── README.md           # This file
```

## Dependencies

- Amazon.Lambda.APIGatewayEvents (2.7.0)
- Amazon.Lambda.Core (2.2.0)
- Amazon.Lambda.RuntimeSupport (1.8.1)
- AWSSDK.DynamoDBv2 (3.7.300.0)

## Building

```powershell
dotnet build
```

## Testing

```powershell
dotnet test
```

## Deployment

The function is deployed using Terraform as part of the main infrastructure. The deployment process:

1. Builds the .NET Core project
2. Creates a deployment package
3. Updates the Lambda function through Terraform

## Environment Variables

- `DYNAMODB_TABLE`: Name of the DynamoDB table
- `ENVIRONMENT`: Deployment environment (e.g., dev, prod)

## Error Handling

The function implements comprehensive error handling:

1. Input validation
2. DynamoDB operation errors
3. System errors

All errors are logged to CloudWatch with appropriate context.

## Monitoring

The function is integrated with CloudWatch for monitoring:

1. **Metrics**:
   - Invocation count
   - Duration
   - Error count
   - Throttled requests

2. **Logs**:
   - Query parameters
   - Execution time
   - Error details

## Performance Considerations

1. **Memory**: Configured for 256MB
2. **Timeout**: 30 seconds
3. **Concurrency**: Limited by DynamoDB read capacity

## Security

1. **IAM Role**: Minimal permissions required
2. **VPC**: Runs in private subnet
3. **Encryption**: Uses AWS KMS for encryption at rest

## Troubleshooting

Common issues and solutions:

1. **Timeout Errors**:
   - Check DynamoDB performance
   - Review query patterns
   - Consider increasing timeout

2. **Throttling**:
   - Monitor CloudWatch metrics
   - Adjust DynamoDB capacity
   - Implement retry logic

3. **Memory Issues**:
   - Monitor memory usage
   - Adjust memory allocation
   - Optimize query patterns

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

[Your License Here] 