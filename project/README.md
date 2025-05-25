# Audit System Project Structure

## Overview
This project implements a comprehensive audit system with automated testing, monitoring, and security features.

## Project Structure

```
project/
├── src/                    # Source code
│   ├── api/               # API Gateway and backend services
│   ├── frontend/          # Frontend application (React 18 + Material-UI)
│   ├── lambda/            # AWS Lambda functions
│   │   ├── audit-query/   # Query service
│   │   └── audit-events/  # Event processing
│   ├── shared/            # Shared code and utilities
│   └── utils/             # Utility functions
│
├── terraform/             # Infrastructure as Code
│   ├── environments/      # Environment-specific configurations
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   ├── modules/          # Reusable Terraform modules
│   │   ├── networking/
│   │   ├── compute/
│   │   ├── storage/
│   │   ├── frontend/
│   │   └── monitoring/
│   └── shared/           # Shared Terraform configurations
│
├── config/             # Configuration files
│   ├── terraform.tfvars.*  # Environment-specific Terraform variables
│   └── monitoring-config.yaml
│
├── docs/               # Documentation
│   ├── api-documentation.md
│   ├── technical-architecture.md
│   ├── deployment-guide.md
│   └── other documentation files
│
└── artifacts/         # Build artifacts and temporary files
```

## Technology Stack

### Frontend
- React 18.2.0
- Material-UI 5.13.0
- TypeScript 5.0.4
- React Query 3.39.3
- Axios 1.4.0

### Backend
- .NET 8.0
- AWS Lambda
- DynamoDB
- API Gateway

### Infrastructure
- Terraform
- AWS CloudWatch
- AWS SNS for alerts

## Setup Instructions

### Prerequisites
- .NET 8.0 SDK
- Node.js >= 16.x
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0.0
- PowerShell 7.x

### Environment Setup
1. Configure AWS credentials:
   ```powershell
   aws configure
   ```

2. Initialize Terraform:
   ```powershell
   Set-Location project/terraform/environments/dev
   terraform init
   ```

3. Install dependencies:
   ```powershell
   # Frontend dependencies
   Set-Location project/src/frontend
   npm install

   # Backend dependencies
   Set-Location project/src/lambda/audit-query
   dotnet restore
   ```

## Testing

### Unit Tests
```powershell
Set-Location project/src/lambda/audit-query.Tests
dotnet test
```

### Load Tests
```powershell
Set-Location project/src/lambda/audit-query.Tests
dotnet test --filter Category=Load
```

### Security Tests
```powershell
Set-Location project/src/lambda/audit-query.Tests
dotnet test --filter Category=Security
```

### Chaos Tests
```powershell
Set-Location project/src/lambda/audit-query.Tests
dotnet test --filter Category=Chaos
```

## Monitoring

### CloudWatch Dashboard
The system includes a comprehensive CloudWatch dashboard with:
- Query execution time metrics
- Total query results
- Successful queries
- DynamoDB capacity units
- Lambda performance metrics

### Alarms
- High error rate alerts
- High latency alerts
- DynamoDB throttling alerts
- System error alerts

## Documentation
- API Documentation: [API Documentation](docs/api-documentation.md)
- Technical Architecture: [Technical Architecture](docs/technical-architecture.md)
- Deployment Guide: [Deployment Guide](docs/deployment-guide.md)

## Contributing
1. Create a feature branch
2. Make your changes
3. Run tests
4. Submit a pull request

## License
This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details. 