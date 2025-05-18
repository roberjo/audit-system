# API Documentation

## Overview

The Audit System API provides endpoints for managing audit events, user authentication, and system configuration. The API is built using AWS API Gateway and follows REST principles.

## Base URL

```
https://api.audit-system.{environment}.example.com/v1
```

## Authentication

All API endpoints require authentication using AWS IAM or Amazon Cognito. Include the authentication token in the Authorization header:

```
Authorization: Bearer <token>
```

## API Endpoints

### Audit Events

#### 1. Create Audit Event

```http
POST /audit-events
```

Creates a new audit event in the system.

**Request Body:**
```json
{
  "eventType": "string",
  "userId": "string",
  "action": "string",
  "resourceId": "string",
  "resourceType": "string",
  "metadata": {
    "key": "value"
  },
  "timestamp": "2024-03-20T10:00:00Z"
}
```

**Response:**
```json
{
  "eventId": "string",
  "status": "string",
  "createdAt": "2024-03-20T10:00:00Z"
}
```

#### 2. Get Audit Event

```http
GET /audit-events/{eventId}
```

Retrieves a specific audit event by ID.

**Response:**
```json
{
  "eventId": "string",
  "eventType": "string",
  "userId": "string",
  "action": "string",
  "resourceId": "string",
  "resourceType": "string",
  "metadata": {
    "key": "value"
  },
  "timestamp": "2024-03-20T10:00:00Z",
  "createdAt": "2024-03-20T10:00:00Z"
}
```

#### 3. List Audit Events

```http
GET /audit-events
```

Retrieves a list of audit events with optional filtering.

**Query Parameters:**
- `startDate` (optional): Filter events after this date
- `endDate` (optional): Filter events before this date
- `eventType` (optional): Filter by event type
- `userId` (optional): Filter by user ID
- `resourceType` (optional): Filter by resource type
- `limit` (optional): Maximum number of events to return (default: 100)
- `nextToken` (optional): Pagination token

**Response:**
```json
{
  "events": [
    {
      "eventId": "string",
      "eventType": "string",
      "userId": "string",
      "action": "string",
      "resourceId": "string",
      "resourceType": "string",
      "metadata": {
        "key": "value"
      },
      "timestamp": "2024-03-20T10:00:00Z",
      "createdAt": "2024-03-20T10:00:00Z"
    }
  ],
  "nextToken": "string"
}
```

### System Configuration

#### 1. Get System Configuration

```http
GET /system/config
```

Retrieves the current system configuration.

**Response:**
```json
{
  "retentionPeriod": "number",
  "obfuscationEnabled": "boolean",
  "notificationSettings": {
    "email": "boolean",
    "slack": "boolean"
  },
  "maxBatchSize": "number"
}
```

#### 2. Update System Configuration

```http
PUT /system/config
```

Updates the system configuration.

**Request Body:**
```json
{
  "retentionPeriod": "number",
  "obfuscationEnabled": "boolean",
  "notificationSettings": {
    "email": "boolean",
    "slack": "boolean"
  },
  "maxBatchSize": "number"
}
```

**Response:**
```json
{
  "status": "string",
  "updatedAt": "2024-03-20T10:00:00Z"
}
```

### Health Check

#### 1. System Health

```http
GET /health
```

Checks the health status of the system components.

**Response:**
```json
{
  "status": "string",
  "components": {
    "dynamodb": "string",
    "aurora": "string",
    "lambda": "string",
    "sns": "string",
    "sqs": "string"
  },
  "timestamp": "2024-03-20T10:00:00Z"
}
```

## Error Responses

All endpoints may return the following error responses:

### 400 Bad Request
```json
{
  "error": {
    "code": "string",
    "message": "string",
    "details": {}
  }
}
```

### 401 Unauthorized
```json
{
  "error": {
    "code": "Unauthorized",
    "message": "Invalid or expired token"
  }
}
```

### 403 Forbidden
```json
{
  "error": {
    "code": "Forbidden",
    "message": "Insufficient permissions"
  }
}
```

### 404 Not Found
```json
{
  "error": {
    "code": "NotFound",
    "message": "Resource not found"
  }
}
```

### 429 Too Many Requests
```json
{
  "error": {
    "code": "TooManyRequests",
    "message": "Rate limit exceeded",
    "retryAfter": "number"
  }
}
```

### 500 Internal Server Error
```json
{
  "error": {
    "code": "InternalServerError",
    "message": "An unexpected error occurred"
  }
}
```

## Rate Limiting

- Default rate limit: 1000 requests per minute per API key
- Rate limit headers included in all responses:
  - `X-RateLimit-Limit`
  - `X-RateLimit-Remaining`
  - `X-RateLimit-Reset`

## Versioning

The API version is included in the URL path. The current version is v1.

## Data Types

### Timestamp
- Format: ISO 8601 (YYYY-MM-DDThh:mm:ssZ)
- Example: "2024-03-20T10:00:00Z"

### UUID
- Format: 8-4-4-4-12 hexadecimal digits
- Example: "123e4567-e89b-12d3-a456-426614174000"

## Webhooks

The system supports webhooks for real-time event notifications.

### 1. Register Webhook

```http
POST /webhooks
```

**Request Body:**
```json
{
  "url": "string",
  "events": ["string"],
  "secret": "string"
}
```

**Response:**
```json
{
  "webhookId": "string",
  "status": "string",
  "createdAt": "2024-03-20T10:00:00Z"
}
```

### 2. Webhook Payload

```json
{
  "eventId": "string",
  "eventType": "string",
  "timestamp": "2024-03-20T10:00:00Z",
  "data": {}
}
```

The webhook payload is signed using HMAC-SHA256. The signature is included in the `X-Webhook-Signature` header. 