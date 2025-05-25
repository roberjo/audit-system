# Audit System Documentation

## Overview
The Audit System is a service that provides audit trail functionality for tracking changes and actions across multiple systems. It uses AWS DynamoDB for storage and provides a REST API for querying audit records.

## Architecture

### Components
- **API Gateway**: Entry point for HTTP requests
- **Lambda Functions**: Process audit events and handle queries
- **DynamoDB**: Stores audit records
- **SNS/SQS**: Message queue for event processing
- **CloudWatch**: Monitoring and logging

### Data Flow
1. Systems send audit events to the API Gateway
2. Events are published to SNS
3. Lambda function processes events and stores them in DynamoDB
4. Query API allows retrieval of audit records

## API Documentation

### Query Audit Records

```http
GET /audit/records
```

#### Query Parameters
- `userId` (optional): Filter by user ID
- `systemId` (optional): Filter by system ID
- `startDate` (optional): Start of date range (ISO 8601)
- `endDate` (optional): End of date range (ISO 8601)
- `pageSize` (optional): Number of records per page (default: 50, max: 1000)
- `lastEvaluatedKey` (optional): Pagination token

#### Response
```json
{
    "items": [
        {
            "userId": "string",
            "timestamp": "string",
            "action": "string",
            "systemId": "string",
            "details": {
                "key": "value"
            }
        }
    ],
    "lastEvaluatedKey": {
        "userId": "string",
        "timestamp": "string"
    }
}
```

## Security

### Authentication
- API Gateway uses IAM authentication
- Lambda functions use IAM roles
- DynamoDB uses IAM policies

### Authorization
- Systems must have valid IAM credentials
- Users must have appropriate permissions
- Audit records are encrypted at rest

## Development

### Prerequisites
- .NET 8 SDK
- AWS CLI configured
- Terraform installed

### Local Development
1. Clone the repository
2. Install dependencies: `dotnet restore`
3. Run tests: `dotnet test`
4. Deploy to dev: `./terraform/scripts/deploy.sh dev`

### Testing
- Unit tests: `dotnet test`
- Integration tests: `dotnet test --filter Category=Integration`
- Load tests: `dotnet test --filter Category=Load`

## Deployment

### Environments
- Development
- Staging
- Production

### Deployment Process
1. Run tests
2. Build package
3. Deploy infrastructure: `./terraform/scripts/deploy.sh <env>`
4. Deploy application
5. Run smoke tests

## Monitoring

### Metrics
- API latency
- Error rates
- DynamoDB capacity
- Lambda execution time

### Alerts
- High error rates
- Capacity issues
- Performance degradation

## Troubleshooting

### Common Issues
1. API Gateway 403 errors
   - Check IAM permissions
   - Verify API key
2. DynamoDB throttling
   - Check capacity units
   - Review query patterns
3. Lambda timeouts
   - Check function timeout
   - Review cold starts

### Logs
- CloudWatch Logs
- X-Ray traces
- DynamoDB streams

## Contributing
1. Fork the repository
2. Create feature branch
3. Make changes
4. Run tests
5. Submit pull request

## License
MIT License 