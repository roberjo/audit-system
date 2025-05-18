# Data Model Documentation

## Overview

This document describes how audit data is stored and organized in the Audit System. It covers both the DynamoDB tables used for high-performance event storage and the Aurora PostgreSQL database used for detailed audit records and reporting. The document includes table schemas, relationships, data types, and retention policies, making it essential for developers working with the system's data layer.

The Audit System uses a combination of Amazon DynamoDB and Amazon Aurora PostgreSQL v2 for data storage. This document outlines the data models for both databases.

## DynamoDB Tables

### 1. Audit Events Table

**Table Name:** `audit_events`

**Primary Key:**
- Partition Key: `event_id` (String)
- Sort Key: `timestamp` (Number)

**Attributes:**
```typescript
{
  event_id: string;          // UUID
  timestamp: number;         // Unix timestamp
  event_type: string;        // Type of audit event
  user_id: string;          // ID of the user who performed the action
  action: string;           // Action performed
  resource_id: string;      // ID of the affected resource
  resource_type: string;    // Type of the affected resource
  metadata: {               // Additional event-specific data
    [key: string]: any;
  };
  created_at: number;       // Unix timestamp
  updated_at: number;       // Unix timestamp
  status: string;          // Event status (e.g., "PROCESSED", "FAILED")
  obfuscated: boolean;     // Whether sensitive data is obfuscated
}
```

**Global Secondary Indexes:**
1. `user_id-timestamp-index`
   - Partition Key: `user_id`
   - Sort Key: `timestamp`

2. `resource_id-timestamp-index`
   - Partition Key: `resource_id`
   - Sort Key: `timestamp`

3. `event_type-timestamp-index`
   - Partition Key: `event_type`
   - Sort Key: `timestamp`

### 2. System Configuration Table

**Table Name:** `system_config`

**Primary Key:**
- Partition Key: `config_key` (String)

**Attributes:**
```typescript
{
  config_key: string;       // Configuration key
  value: any;              // Configuration value
  data_type: string;       // Data type of the value
  updated_at: number;      // Unix timestamp
  updated_by: string;      // User ID who last updated
  version: number;         // Version number for optimistic locking
}
```

## Aurora PostgreSQL Tables

### 1. Users Table

```sql
CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    role VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
```

### 2. Resources Table

```sql
CREATE TABLE resources (
    resource_id UUID PRIMARY KEY,
    resource_type VARCHAR(100) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

CREATE INDEX idx_resources_type ON resources(resource_type);
CREATE INDEX idx_resources_status ON resources(status);
```

### 3. Audit Event Details Table

```sql
CREATE TABLE audit_event_details (
    event_id UUID PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    user_id UUID NOT NULL,
    action VARCHAR(100) NOT NULL,
    resource_id UUID,
    resource_type VARCHAR(100),
    old_value JSONB,
    new_value JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id)
);

CREATE INDEX idx_audit_event_details_user_id ON audit_event_details(user_id);
CREATE INDEX idx_audit_event_details_resource_id ON audit_event_details(resource_id);
CREATE INDEX idx_audit_event_details_event_type ON audit_event_details(event_type);
CREATE INDEX idx_audit_event_details_created_at ON audit_event_details(created_at);
```

### 4. System Logs Table

```sql
CREATE TABLE system_logs (
    log_id UUID PRIMARY KEY,
    level VARCHAR(20) NOT NULL,
    component VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    stack_trace TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_system_logs_level ON system_logs(level);
CREATE INDEX idx_system_logs_component ON system_logs(component);
CREATE INDEX idx_system_logs_created_at ON system_logs(created_at);
```

### 5. Webhooks Table

```sql
CREATE TABLE webhooks (
    webhook_id UUID PRIMARY KEY,
    url VARCHAR(2048) NOT NULL,
    events JSONB NOT NULL,
    secret VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    last_triggered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

CREATE INDEX idx_webhooks_status ON webhooks(status);
CREATE INDEX idx_webhooks_created_at ON webhooks(created_at);
```

## Data Types

### Common Data Types

1. **UUID**
   - Format: 8-4-4-4-12 hexadecimal digits
   - Example: "123e4567-e89b-12d3-a456-426614174000"

2. **Timestamp**
   - Format: ISO 8601 with timezone
   - Example: "2024-03-20T10:00:00Z"

3. **JSONB**
   - Used for flexible schema attributes
   - Supports indexing and querying

### Enums

1. **Event Types**
```typescript
enum EventType {
  USER_LOGIN = "USER_LOGIN",
  USER_LOGOUT = "USER_LOGOUT",
  RESOURCE_CREATE = "RESOURCE_CREATE",
  RESOURCE_UPDATE = "RESOURCE_UPDATE",
  RESOURCE_DELETE = "RESOURCE_DELETE",
  CONFIG_CHANGE = "CONFIG_CHANGE",
  SYSTEM_ERROR = "SYSTEM_ERROR"
}
```

2. **User Roles**
```typescript
enum UserRole {
  ADMIN = "ADMIN",
  AUDITOR = "AUDITOR",
  VIEWER = "VIEWER"
}
```

3. **Resource Types**
```typescript
enum ResourceType {
  USER = "USER",
  CONFIG = "CONFIG",
  WEBHOOK = "WEBHOOK"
}
```

## Data Relationships

1. **Audit Events to Users**
   - One-to-Many relationship
   - An audit event is associated with one user
   - A user can have multiple audit events

2. **Audit Events to Resources**
   - One-to-Many relationship
   - An audit event can be associated with one resource
   - A resource can have multiple audit events

3. **Webhooks to Events**
   - Many-to-Many relationship
   - A webhook can be triggered by multiple event types
   - An event type can trigger multiple webhooks

## Data Retention

1. **DynamoDB**
   - Audit Events: 90 days
   - System Config: Indefinite

2. **Aurora PostgreSQL**
   - Users: Indefinite
   - Resources: Indefinite
   - Audit Event Details: 90 days
   - System Logs: 30 days
   - Webhooks: Indefinite

## Data Migration

1. **DynamoDB to Aurora**
   - Daily batch migration of audit events
   - Real-time streaming for critical events

2. **Aurora to S3**
   - Weekly archival of old data
   - Compressed Parquet format
   - Partitioned by date 