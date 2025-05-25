# Audit System Architecture Diagram

## High-Level System Architecture

```mermaid
graph TB
    subgraph Client["Client Applications"]
        WebApp["Web Application"]
        MobileApp["Mobile Application"]
        API["API Clients"]
    end

    subgraph Frontend["Frontend Layer"]
        ReactApp["React Application"]
        CloudFront["CloudFront CDN"]
        S3Static["S3 Static Assets"]
    end

    subgraph API["API Layer"]
        APIGateway["API Gateway"]
        Authorizer["Custom Authorizer"]
    end

    subgraph Processing["Event Processing"]
        SNS["SNS Topics"]
        SQS["SQS Queues"]
        DLQ["Dead Letter Queue"]
        Lambda["Lambda Functions"]
    end

    subgraph Storage["Storage Layer"]
        DynamoDB["DynamoDB Table"]
    end

    subgraph Monitoring["Monitoring & Alerting"]
        CloudWatch["CloudWatch"]
        Alarms["CloudWatch Alarms"]
        SNSAlerts["SNS Alerts"]
    end

    %% Client to Frontend connections
    WebApp --> ReactApp
    MobileApp --> ReactApp
    API --> ReactApp

    %% Frontend to API connections
    ReactApp --> APIGateway
    CloudFront --> S3Static
    S3Static --> ReactApp

    %% API to Processing connections
    APIGateway --> Authorizer
    APIGateway --> SNS
    SNS --> SQS
    SQS --> Lambda
    Lambda --> DLQ

    %% Processing to Storage connections
    Lambda --> DynamoDB

    %% Monitoring connections
    Lambda --> CloudWatch
    DynamoDB --> CloudWatch
    CloudWatch --> Alarms
    Alarms --> SNSAlerts

    %% Styling
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:white;
    classDef client fill:#4CAF50,stroke:#2E7D32,stroke-width:2px,color:white;
    classDef processing fill:#2196F3,stroke:#1565C0,stroke-width:2px,color:white;
    classDef storage fill:#9C27B0,stroke:#6A1B9A,stroke-width:2px,color:white;
    classDef monitoring fill:#F44336,stroke:#B71C1C,stroke-width:2px,color:white;

    class WebApp,MobileApp,API client;
    class ReactApp,CloudFront,S3Static aws;
    class APIGateway,Authorizer,SNS,SQS,DLQ,Lambda processing;
    class DynamoDB storage;
    class CloudWatch,Alarms,SNSAlerts monitoring;
```

## Event Processing Flow

```mermaid
sequenceDiagram
    participant Client
    participant API as API Gateway
    participant SNS
    participant SQS
    participant Lambda
    participant DynamoDB
    participant CloudWatch

    Client->>API: Send Audit Event
    API->>SNS: Publish Event
    SNS->>SQS: Queue Event
    SQS->>Lambda: Trigger Processing
    Lambda->>DynamoDB: Store Event
    Lambda->>CloudWatch: Log Metrics
    Lambda-->>SQS: Delete Message
    SQS-->>Client: Acknowledge
```

## Security Architecture

```mermaid
graph TB
    subgraph Authentication["Authentication Layer"]
        IAM["IAM Roles"]
        Cognito["Amazon Cognito"]
        JWT["JWT Validation"]
    end

    subgraph Authorization["Authorization Layer"]
        Policies["IAM Policies"]
        Groups["User Groups"]
        Permissions["Resource Permissions"]
    end

    subgraph Protection["Data Protection"]
        Encryption["Encryption"]
        TLS["TLS/SSL"]
        KMS["KMS Keys"]
    end

    subgraph Monitoring["Security Monitoring"]
        CloudTrail["CloudTrail"]
        GuardDuty["GuardDuty"]
        SecurityHub["Security Hub"]
    end

    %% Authentication flow
    IAM --> Policies
    Cognito --> JWT
    JWT --> Policies

    %% Authorization flow
    Policies --> Groups
    Groups --> Permissions

    %% Protection flow
    Encryption --> KMS
    TLS --> KMS

    %% Monitoring flow
    CloudTrail --> SecurityHub
    GuardDuty --> SecurityHub

    %% Styling
    classDef auth fill:#4CAF50,stroke:#2E7D32,stroke-width:2px,color:white;
    classDef protect fill:#2196F3,stroke:#1565C0,stroke-width:2px,color:white;
    classDef monitor fill:#F44336,stroke:#B71C1C,stroke-width:2px,color:white;

    class IAM,Cognito,JWT auth;
    class Policies,Groups,Permissions,Encryption,TLS,KMS protect;
    class CloudTrail,GuardDuty,SecurityHub monitor;
```

## Component Descriptions

### Frontend Layer
- **React Application**: Main web interface for audit log visualization
- **CloudFront CDN**: Content delivery network for static assets
- **S3 Static Assets**: Storage for frontend static files

### API Layer
- **API Gateway**: REST API endpoint management
- **Custom Authorizer**: JWT token validation and authorization

### Event Processing
- **SNS Topics**: Event publishing and distribution
- **SQS Queues**: Event buffering and processing
- **Dead Letter Queue**: Failed event handling
- **Lambda Functions**: Event processing and storage

### Storage Layer
- **DynamoDB Table**: Audit event storage with TTL

### Monitoring & Alerting
- **CloudWatch**: Metrics and logging
- **CloudWatch Alarms**: Threshold monitoring
- **SNS Alerts**: Notification distribution

### Security Components
- **IAM Roles**: Service permissions
- **Amazon Cognito**: User authentication
- **JWT Validation**: Token verification
- **KMS**: Key management
- **CloudTrail**: API activity logging
- **GuardDuty**: Threat detection
- **Security Hub**: Security posture management 