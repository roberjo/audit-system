# Technical Architecture Document

## System Overview

The Audit System is a cloud-native, event-driven architecture designed to capture, process, and analyze audit events from multiple wealth management applications. The system leverages AWS serverless services for scalability and cost-efficiency.

## Technology Stack

### 1. Infrastructure & DevOps
- **Infrastructure as Code**: Terraform Cloud
- **Secrets Management**: HashiCorp Vault
- **CI/CD**: AWS CodePipeline with CodeBuild
- **Container Registry**: Amazon ECR

### 2. Backend Services
- **API Layer**: AWS API Gateway
- **Serverless Functions**: 
  - AWS Lambda with .NET Core 8
  - AWS Lambda with Python
  - AWS Lambda with TypeScript
- **Message Queuing**: 
  - AWS SNS for event publishing
  - AWS SQS for message processing
- **Databases**:
  - Amazon DynamoDB (NoSQL)
  - Amazon Aurora PostgreSQL v2 (SQL)
- **Storage**: Amazon S3

### 3. Frontend
- **Framework**: React 18
- **Build Tool**: Vite
- **State Management**: MobX
- **UI Components**: Material-UI or Ant Design
- **API Client**: Axios

## Architecture Components

### 1. Event Producers
- **Technology Stack**: 
  - .NET Core 8 applications
  - TypeScript applications
  - Python applications
- **Responsibilities**:
  - Generate audit events in standardized JSON format
  - Integrate with Micro Focus Voltage for data obfuscation
  - Publish events to AWS SNS topic
- **Integration Points**:
  - AWS SNS Topic
  - Micro Focus Voltage API
  - HashiCorp Vault for secrets

### 2. Event Ingestion Layer
- **AWS SNS Topic**
  - Purpose: Centralized event collection
  - Configuration: Standard SNS topic with appropriate access policies
  - Message Format: JSON with standardized schema

- **AWS SQS Queue**
  - Type: Standard Queue
  - Configuration:
    - Message retention: 14 days
    - Visibility timeout: 5 minutes
    - Dead Letter Queue enabled
  - Error Handling: Failed messages routed to DLQ

### 3. Processing Layer
- **AWS Lambda (.NET Core 8)**
  - Runtime: .NET Core 8
  - Memory: 1024MB
  - Timeout: 5 minutes
  - Batch Size: 100 messages
  - Functions:
    - Event validation
    - Data transformation
    - DynamoDB persistence
  - Error Handling: DLQ integration

- **AWS Lambda (Python)**
  - Runtime: Python 3.9
  - Memory: 1024MB
  - Timeout: 5 minutes
  - Functions:
    - Data enrichment
    - Complex transformations
    - External API integrations

- **AWS Lambda (TypeScript)**
  - Runtime: Node.js 18.x
  - Memory: 1024MB
  - Timeout: 5 minutes
  - Functions:
    - API handlers
    - Business logic
    - Data validation

### 4. Storage Layer
- **AWS DynamoDB**
  - Mode: On-Demand Capacity
  - Encryption: AWS KMS
  - Streams: Enabled for real-time processing
  - Schema:
    - Partition Key: event_id (String)
    - Sort Key: timestamp (Number)
    - Attributes: As per audit event schema

- **Amazon Aurora PostgreSQL v2**
  - Version: PostgreSQL 14
  - Instance Class: db.r6g.large (minimum)
  - Storage: 100GB (auto-scaling)
  - Multi-AZ: Enabled
  - Encryption: AWS KMS
  - Backup: Automated daily snapshots

### 5. API Layer
- **AWS API Gateway**
  - Type: REST API
  - Authentication: IAM/Cognito
  - Rate Limiting: Enabled
  - Caching: API Gateway cache
  - Documentation: OpenAPI/Swagger

### 6. Frontend Application
- **React 18 Application**
  - Build Tool: Vite
  - State Management: MobX
  - Routing: React Router
  - HTTP Client: Axios
  - UI Framework: Material-UI/Ant Design
  - Testing: Jest + React Testing Library

## Security Architecture

### 1. Data Protection
- **In Transit**:
  - TLS 1.2+ for all communications
  - AWS KMS for key management
  - Micro Focus Voltage for data obfuscation

- **At Rest**:
  - DynamoDB: AWS KMS encryption
  - Aurora: AWS KMS encryption
  - S3: AWS KMS encryption

### 2. Access Control
- **AWS IAM**:
  - Least privilege principle
  - Role-based access
  - Resource-based policies

- **HashiCorp Vault**:
  - Secrets management
  - Dynamic secrets
  - Access control

- **Database**:
  - Role-based access control
  - Network policies
  - Resource monitors

## Monitoring and Observability

### 1. Logging
- **AWS CloudWatch Logs**:
  - Lambda function logs
  - Application logs
  - Access logs
  - Database logs

### 2. Metrics
- **AWS CloudWatch Metrics**:
  - Lambda invocations
  - SQS queue length
  - DynamoDB capacity
  - Aurora performance
  - API Gateway metrics

### 3. Alarms
- **Critical Alarms**:
  - High error rates
  - Queue length thresholds
  - Processing delays
  - Database performance
  - API latency

## Deployment Architecture

### 1. Infrastructure as Code
- **Terraform Cloud**:
  - Workspace configuration
  - State management
  - Resource definitions
  - Security configurations
  - Network settings

### 2. CI/CD Pipeline
- **AWS CodePipeline**:
  - Source code management
  - Build process
  - Deployment automation
  - Testing integration
  - Infrastructure deployment

## Performance Considerations

### 1. Scalability
- Lambda concurrency limits
- DynamoDB on-demand capacity
- Aurora read replicas
- SQS message batching
- API Gateway caching

### 2. Latency
- End-to-end processing time targets
- Batch processing windows
- Database query optimization
- API response times

## Disaster Recovery

### 1. Data Protection
- DynamoDB point-in-time recovery
- Aurora automated backups
- S3 versioning
- Cross-region replication

### 2. High Availability
- Multi-AZ deployment
- Aurora multi-AZ
- Cross-region replication
- Backup and restore procedures

## Cost Optimization

### 1. Resource Management
- Lambda memory optimization
- DynamoDB capacity planning
- Aurora instance sizing
- S3 lifecycle policies
- API Gateway caching

### 2. Monitoring
- Cost allocation tags
- Budget alerts
- Resource utilization tracking
- Reserved capacity planning 