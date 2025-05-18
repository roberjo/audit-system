# Audit System Project Structure

## Overview
This project implements a comprehensive audit system with blue/green deployment capabilities, automated testing, and monitoring.

## Project Structure

```
project/
├── src/                    # Source code
│   ├── api/               # API Gateway and backend services
│   ├── frontend/          # Frontend application
│   ├── lambda/            # AWS Lambda functions
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
│   │   └── blue-green/
│   └── shared/           # Shared Terraform configurations
│
├── tests/                # Test suites
│   ├── unit/            # Unit tests
│   ├── integration/     # Integration tests
│   ├── e2e/            # End-to-end tests
│   ├── performance/    # Performance tests
│   └── security/       # Security tests
│
├── scripts/             # Automation scripts
│   ├── deployment/     # Deployment scripts
│   ├── monitoring/     # Monitoring scripts
│   ├── security/       # Security scripts
│   └── health-checks/  # Health check scripts
│
├── config/             # Configuration files
│   ├── terraform.tfvars.*  # Environment-specific Terraform variables
│   ├── blue-green-config.yaml
│   ├── monitoring-config.yaml
│   └── security-config.yaml
│
├── docs/               # Documentation
│   ├── ci-cd-pipeline.md
│   └── other documentation files
│
└── artifacts/         # Build artifacts and temporary files
```

## Setup Instructions

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0.0
- Node.js >= 16.x
- Python >= 3.8
- PowerShell 7.x

### Environment Setup
1. Configure AWS credentials:
   ```powershell
   aws configure
   ```

2. Initialize Terraform:
   ```powershell
   cd project/terraform/environments/dev
   terraform init
   ```

3. Install dependencies:
   ```powershell
   # Frontend dependencies
   cd project/src/frontend
   npm install

   # Backend dependencies
   cd project/src/api
   npm install
   ```

### Development
1. Start development environment:
   ```powershell
   ./scripts/deployment/start-dev.ps1
   ```

2. Run tests:
   ```powershell
   ./scripts/run-tests.ps1
   ```

### Deployment
1. Deploy to development:
   ```powershell
   ./scripts/deployment/deploy.ps1 -Environment dev
   ```

2. Deploy to staging:
   ```powershell
   ./scripts/deployment/deploy.ps1 -Environment staging
   ```

3. Deploy to production:
   ```powershell
   ./scripts/deployment/deploy.ps1 -Environment prod
   ```

## Monitoring and Maintenance

### Health Checks
- Run health checks:
  ```powershell
  ./scripts/health-checks/run-health-checks.ps1
  ```

### Monitoring
- View monitoring dashboard:
  ```powershell
  ./scripts/monitoring/open-dashboard.ps1
  ```

### Security
- Run security scans:
  ```powershell
  ./scripts/security/run-security-scan.ps1
  ```

## Documentation
- CI/CD Pipeline: [CI/CD Pipeline Documentation](docs/ci-cd-pipeline.md)
- Infrastructure: [Infrastructure Documentation](docs/infrastructure.md)
- API Documentation: [API Documentation](docs/api.md)
- Frontend Documentation: [Frontend Documentation](docs/frontend.md)

## Contributing
1. Create a feature branch
2. Make your changes
3. Run tests
4. Submit a pull request

## License
This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details. 