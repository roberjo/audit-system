# API Documentation

## Overview

This document provides a complete reference for the Audit System's REST API. It details all available endpoints, request/response formats, authentication requirements, and error handling. Whether you're integrating a new application or building a client, this guide will help you understand how to interact with the Audit System programmatically. All endpoints are secured using AWS IAM and Amazon Cognito, ensuring secure access to audit data.

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