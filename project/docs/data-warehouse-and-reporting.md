# Data Warehouse and Reporting Architecture

## Overview

The Audit System's data warehouse solution is designed to provide comprehensive audit data management, analytics, and reporting capabilities. This architecture ensures reliable data capture, efficient storage, and powerful analysis tools for audit events and compliance monitoring.

### Key Components and Their Roles

1. **Data Ingestion Layer**
   - **Kinesis Stream**: Captures real-time audit events with guaranteed delivery
   - **Snowpipe**: Provides continuous data loading with automatic scaling
   - **Error Handling**: Implements dead-letter queues and retry mechanisms

2. **Storage Layer**
   - **Snowflake Data Warehouse**: Provides scalable, secure storage
   - **Data Marts**: Optimized for specific reporting needs
   - **Time Travel**: Enables historical data analysis and point-in-time recovery

3. **Processing Layer**
   - **ETL Processes**: Transform and enrich raw audit data
   - **Aggregation Jobs**: Generate summary statistics and metrics
   - **Compliance Checks**: Automated validation of audit data

4. **Reporting Layer**
   - **Power BI Integration**: Interactive dashboards and visualizations
   - **SSRS Reports**: Scheduled regulatory and compliance reports
   - **Custom Analytics**: Advanced data analysis capabilities

### Data Flow Architecture

```
[Audit Events] → [Kinesis Stream] → [Snowpipe] → [Snowflake] → [Data Marts]
     ↑              ↑                  ↑             ↑             ↑
     │              │                  │             │             │
     └──────────────┴──────────────────┴─────────────┴─────────────┘
                    Error Handling & Monitoring
```

#### Example Data Flow

1. **Event Generation**
   ```json
   {
     "event_id": "evt_20240320143000_001",
     "timestamp": "2024-03-20T14:30:00Z",
     "source": "API_GATEWAY",
     "event_type": "DATA_ACCESS",
     "user": {
       "id": "usr_789",
       "role": "DATA_ANALYST",
       "department": "FINANCE"
     },
     "action": {
       "type": "READ",
       "resource": "CUSTOMER_DATA",
       "sensitivity": "HIGH"
     }
   }
   ```

2. **Kinesis Stream Processing**
   ```python
   # Example Kinesis stream configuration
   {
     "StreamName": "audit-events-stream",
     "ShardCount": 4,
     "StreamMode": "PROVISIONED",
     "RetentionPeriodHours": 24,
     "EnhancedMonitoring": {
       "ShardLevelMetrics": [
         "IncomingBytes",
         "OutgoingBytes",
         "WriteProvisionedThroughputExceeded"
       ]
     }
   }
   ```

3. **Snowpipe Loading**
   ```sql
   -- Example Snowpipe configuration
   CREATE PIPE audit_events_pipe
   AUTO_INGEST = TRUE
   AS
   COPY INTO audit_events_raw
   FROM @audit_events_stage
   FILE_FORMAT = (TYPE = 'JSON')
   PATTERN = '.*audit-events-.*.json';
   ```

### Key Features and Benefits

1. **Real-time Processing**
   - Sub-second event capture
   - Near real-time data availability
   - Immediate compliance monitoring

2. **Scalability**
   - Automatic scaling of resources
   - Support for high-volume event processing
   - Efficient storage management

3. **Data Quality**
   - Schema validation
   - Data completeness checks
   - Automated error handling

4. **Security**
   - Encryption at rest and in transit
   - Role-based access control
   - Audit trail of all operations

### Performance Characteristics

1. **Ingestion Performance**
   - Up to 10,000 events per second
   - 99.9% event delivery guarantee
   - Sub-5 second end-to-end latency

2. **Query Performance**
   - Sub-second response for common queries
   - Efficient handling of complex analytics
   - Optimized for time-series analysis

3. **Storage Efficiency**
   - Automatic data compression
   - Efficient columnar storage
   - Smart data partitioning

### Monitoring and Maintenance

1. **Health Checks**
   ```sql
   -- Example monitoring query
   SELECT 
     DATE_TRUNC('hour', timestamp) as hour,
     COUNT(*) as event_count,
     COUNT(DISTINCT user_id) as unique_users,
     AVG(processing_time) as avg_processing_time
   FROM audit_events_mart
   WHERE timestamp > DATEADD(hour, -1, CURRENT_TIMESTAMP())
   GROUP BY 1
   ORDER BY 1;
   ```

2. **Alerting**
   ```yaml
   alerts:
     high_latency:
       condition: "processing_time > 5 seconds"
       threshold: 100
       window: "5 minutes"
       action: "notify_team"
     
     error_rate:
       condition: "error_count / total_events > 0.01"
       threshold: 50
       window: "1 hour"
       action: "create_incident"
   ```

3. **Maintenance Tasks**
   ```sql
   -- Example maintenance procedure
   CREATE OR REPLACE PROCEDURE perform_maintenance()
   RETURNS STRING
   AS
   $$
   BEGIN
     -- Optimize table clustering
     ALTER TABLE audit_events_mart CLUSTER BY (timestamp);
     
     -- Update statistics
     ANALYZE TABLE audit_events_mart;
     
     -- Clean up temporary tables
     DROP TABLE IF EXISTS temp_audit_events;
     
     RETURN 'Maintenance completed successfully';
   END;
   $$;
   ```

### Cost Optimization

1. **Storage Optimization**
   - Automatic data tiering
   - Compression strategies
   - Archival policies

2. **Compute Optimization**
   - Warehouse auto-scaling
   - Query optimization
   - Resource monitoring

3. **Data Lifecycle**
   - Hot data (last 30 days)
   - Warm data (30-90 days)
   - Cold data (90+ days)

This architecture provides a robust foundation for audit reporting and analytics, ensuring compliance with regulatory requirements while maintaining performance and cost efficiency.

## Data Warehouse Architecture

### 1. Data Flow
```
[Audit Events] → [Kinesis Stream] → [Snowpipe] → [Snowflake] → [Data Marts]
```

### 2. Components

#### Kinesis Stream
- Captures real-time audit events
- Provides buffering and reliability
- Enables parallel processing
- Maintains event ordering

#### Snowpipe
- Automatically loads data from Kinesis to Snowflake
- Provides near real-time data ingestion
- Handles data transformation
- Manages error recovery

#### Snowflake Data Warehouse
- Stores historical audit data
- Provides data marts for different reporting needs
- Enables data sharing and collaboration
- Supports time travel for historical analysis

### 3. Data Marts

The data marts are designed to provide optimized access to audit data for different reporting and analysis needs. Each mart is specifically structured to support particular use cases while maintaining data integrity and performance.

#### Audit Events Mart
The Audit Events Mart stores the core audit trail data with detailed event information. This mart is optimized for querying specific events and analyzing audit patterns.

```sql
CREATE TABLE audit_events_mart (
    event_id VARCHAR,           -- Unique identifier for each audit event
    event_type VARCHAR,         -- Type of audit event (e.g., 'LOGIN', 'DATA_ACCESS', 'CONFIG_CHANGE')
    user_id VARCHAR,            -- ID of the user who performed the action
    action VARCHAR,             -- Specific action taken (e.g., 'CREATE', 'READ', 'UPDATE', 'DELETE')
    resource_id VARCHAR,        -- ID of the resource affected
    resource_type VARCHAR,      -- Type of resource (e.g., 'FILE', 'DATABASE', 'CONFIG')
    timestamp TIMESTAMP,        -- When the event occurred
    environment VARCHAR,        -- Environment where event occurred (e.g., 'PROD', 'DEV', 'TEST')
    region VARCHAR,            -- AWS region or data center location
    metadata VARIANT           -- Additional event-specific data in JSON format
);

-- Example of event data:
{
    "event_id": "evt_123456",
    "event_type": "DATA_ACCESS",
    "user_id": "usr_789",
    "action": "READ",
    "resource_id": "doc_456",
    "resource_type": "DOCUMENT",
    "timestamp": "2024-03-20 14:30:00",
    "environment": "PROD",
    "region": "us-east-1",
    "metadata": {
        "ip_address": "192.168.1.1",
        "user_agent": "Chrome/120.0",
        "access_method": "API",
        "data_classification": "CONFIDENTIAL"
    }
}
```

#### User Activity Mart
The User Activity Mart provides aggregated user activity data for analyzing user behavior patterns and access trends. This mart is optimized for user-centric reporting and analysis.

```sql
CREATE TABLE user_activity_mart (
    user_id VARCHAR,            -- Unique identifier for the user
    activity_type VARCHAR,      -- Type of activity (e.g., 'LOGIN', 'DATA_ACCESS', 'REPORT_GENERATION')
    event_count INTEGER,        -- Number of events of this type
    first_activity TIMESTAMP,   -- First occurrence of this activity type
    last_activity TIMESTAMP,    -- Most recent occurrence of this activity type
    resource_access_count INTEGER, -- Number of unique resources accessed
    avg_session_duration INTEGER,  -- Average session duration in minutes
    risk_score DECIMAL(3,2),    -- Calculated risk score based on activity patterns
    last_risk_assessment TIMESTAMP -- When the risk score was last calculated
);

-- Example of aggregated user activity:
{
    "user_id": "usr_789",
    "activity_type": "DATA_ACCESS",
    "event_count": 150,
    "first_activity": "2024-03-01 09:00:00",
    "last_activity": "2024-03-20 16:45:00",
    "resource_access_count": 45,
    "avg_session_duration": 30,
    "risk_score": 0.15,
    "last_risk_assessment": "2024-03-20 17:00:00"
}
```

#### Compliance Mart
The Compliance Mart tracks compliance-related events and violations, supporting regulatory reporting and compliance monitoring.

```sql
CREATE TABLE compliance_mart (
    compliance_rule_id VARCHAR,     -- Unique identifier for the compliance rule
    event_type VARCHAR,             -- Type of compliance event
    violation_count INTEGER,        -- Number of violations for this rule
    last_violation TIMESTAMP,       -- Most recent violation
    resolution_status VARCHAR,       -- Current status (e.g., 'OPEN', 'IN_PROGRESS', 'RESOLVED')
    severity_level VARCHAR,         -- Severity of the violation (e.g., 'LOW', 'MEDIUM', 'HIGH')
    affected_resources INTEGER,     -- Number of resources affected
    resolution_time INTEGER,        -- Average time to resolve in hours
    compliance_score DECIMAL(3,2),  -- Overall compliance score for this rule
    last_assessment TIMESTAMP       -- When the compliance score was last calculated
);

-- Example of compliance data:
{
    "compliance_rule_id": "rule_456",
    "event_type": "DATA_RETENTION",
    "violation_count": 3,
    "last_violation": "2024-03-19 10:15:00",
    "resolution_status": "IN_PROGRESS",
    "severity_level": "HIGH",
    "affected_resources": 5,
    "resolution_time": 24,
    "compliance_score": 0.85,
    "last_assessment": "2024-03-20 00:00:00"
}
```

### Data Mart Processing

#### 1. Data Loading Process
```sql
-- Daily data refresh process
CREATE OR REPLACE PROCEDURE refresh_data_marts()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Refresh Audit Events Mart
    MERGE INTO audit_events_mart a
    USING raw_audit_events r
    ON a.event_id = r.event_id
    WHEN MATCHED THEN
        UPDATE SET /* update fields */
    WHEN NOT MATCHED THEN
        INSERT /* insert new records */;

    -- Refresh User Activity Mart
    MERGE INTO user_activity_mart u
    USING (
        SELECT 
            user_id,
            activity_type,
            COUNT(*) as event_count,
            MIN(timestamp) as first_activity,
            MAX(timestamp) as last_activity,
            COUNT(DISTINCT resource_id) as resource_access_count
        FROM raw_audit_events
        GROUP BY user_id, activity_type
    ) s
    ON u.user_id = s.user_id AND u.activity_type = s.activity_type
    WHEN MATCHED THEN
        UPDATE SET /* update aggregated fields */
    WHEN NOT MATCHED THEN
        INSERT /* insert new aggregated records */;

    -- Refresh Compliance Mart
    MERGE INTO compliance_mart c
    USING (
        SELECT 
            compliance_rule_id,
            event_type,
            COUNT(*) as violation_count,
            MAX(timestamp) as last_violation
        FROM raw_audit_events
        WHERE is_violation = TRUE
        GROUP BY compliance_rule_id, event_type
    ) v
    ON c.compliance_rule_id = v.compliance_rule_id
    WHEN MATCHED THEN
        UPDATE SET /* update compliance metrics */
    WHEN NOT MATCHED THEN
        INSERT /* insert new compliance records */;

    RETURN 'Data marts refreshed successfully';
END;
$$;
```

#### 2. Data Retention and Archival
```sql
-- Data retention policy
CREATE OR REPLACE PROCEDURE manage_data_retention()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Archive old audit events
    INSERT INTO audit_events_archive
    SELECT * FROM audit_events_mart
    WHERE timestamp < DATEADD(year, -2, CURRENT_TIMESTAMP());

    -- Delete archived records from main table
    DELETE FROM audit_events_mart
    WHERE timestamp < DATEADD(year, -2, CURRENT_TIMESTAMP());

    -- Compress archived data
    ALTER TABLE audit_events_archive CLUSTER BY (timestamp);

    RETURN 'Data retention completed successfully';
END;
$$;
```

#### 3. Performance Optimization
```sql
-- Create optimized views for common queries
CREATE OR REPLACE VIEW vw_user_activity_summary AS
SELECT 
    u.user_id,
    u.activity_type,
    u.event_count,
    u.last_activity,
    c.compliance_score
FROM user_activity_mart u
LEFT JOIN compliance_mart c ON u.user_id = c.user_id
WHERE u.last_activity > DATEADD(day, -30, CURRENT_TIMESTAMP());

-- Create materialized view for compliance reporting
CREATE OR REPLACE MATERIALIZED VIEW mv_compliance_dashboard AS
SELECT 
    compliance_rule_id,
    COUNT(*) as total_violations,
    AVG(resolution_time) as avg_resolution_time,
    MIN(compliance_score) as min_compliance_score
FROM compliance_mart
GROUP BY compliance_rule_id;
```

## Reporting Architecture

### 1. Report Generation Technology

#### Power BI Integration
- Direct connection to Snowflake
- Real-time dashboards
- Scheduled report generation
- Export to multiple formats (PDF, Excel, CSV)

#### SSRS (SQL Server Reporting Services)
- Scheduled report generation
- PDF and Excel exports
- Email distribution
- Role-based access control

### 2. Report Types

#### Regulatory Reports
1. **Access Control Report**
   - User access patterns
   - Permission changes
   - Failed access attempts
   - Compliance status

2. **Data Access Report**
   - Sensitive data access
   - Data modification history
   - Export activities
   - Access patterns

3. **System Change Report**
   - Configuration changes
   - System updates
   - Security changes
   - Infrastructure modifications

#### Operational Reports
1. **Activity Summary**
   - Daily/weekly/monthly activity
   - User engagement metrics
   - System performance
   - Error rates

2. **Compliance Dashboard**
   - Policy violations
   - Resolution status
   - Risk indicators
   - Compliance trends

### 3. Report Scheduling

```yaml
report_schedules:
  daily_reports:
    - name: "Daily Access Control Report"
      schedule: "0 0 * * *"
      format: "PDF"
      distribution: ["compliance@company.com"]
      
  weekly_reports:
    - name: "Weekly Compliance Summary"
      schedule: "0 0 * * 1"
      format: "PDF"
      distribution: ["audit@company.com"]
      
  monthly_reports:
    - name: "Monthly Regulatory Report"
      schedule: "0 0 1 * *"
      format: "PDF"
      distribution: ["regulatory@company.com"]
```

### 4. Report Distribution

#### Email Distribution
- Secure email delivery
- Role-based distribution lists
- Audit trail of report distribution
- Encryption for sensitive reports

#### Portal Access
- Secure web portal for report access
- Role-based permissions
- Report versioning
- Download tracking

## Implementation Steps

1. **Data Pipeline Setup**
   ```bash
   # Configure Kinesis Stream
   aws kinesis create-stream --stream-name audit-events --shard-count 4
   
   # Set up Snowpipe
   snowsql -c audit_system -f setup_snowpipe.sql
   ```

2. **Snowflake Configuration**
   ```sql
   -- Create warehouse
   CREATE WAREHOUSE audit_wh
   WITH WAREHOUSE_SIZE = 'MEDIUM'
   AUTO_SUSPEND = 60
   AUTO_RESUME = TRUE;
   
   -- Create database
   CREATE DATABASE audit_dw;
   
   -- Create schemas
   CREATE SCHEMA audit_dw.raw;
   CREATE SCHEMA audit_dw.mart;
   ```

3. **Report Setup**
   ```powershell
   # Configure SSRS
   Install-Module -Name ReportingServicesTools
   Install-Ssrs -Path "C:\SSRS" -Edition "Standard"
   
   # Set up Power BI Gateway
   Install-PowerBIGateway -Path "C:\PowerBIGateway"
   ```

## Monitoring and Maintenance

### 1. Pipeline Monitoring
- Kinesis stream metrics
- Snowpipe ingestion status
- Data latency tracking
- Error rate monitoring

### 2. Report Monitoring
- Report generation status
- Distribution tracking
- Access logging
- Performance metrics

### 3. Maintenance Tasks
- Daily data validation
- Weekly performance optimization
- Monthly storage cleanup
- Quarterly compliance review

## Security Considerations

1. **Data Protection**
   - Encryption at rest and in transit
   - Role-based access control
   - Data masking for sensitive fields
   - Audit logging of all access

2. **Report Security**
   - Secure report storage
   - Encrypted report distribution
   - Access control for report viewing
   - Audit trail of report access

## Cost Optimization

1. **Storage Optimization**
   - Data lifecycle management
   - Compression strategies
   - Archival policies
   - Cleanup procedures

2. **Compute Optimization**
   - Warehouse auto-scaling
   - Query optimization
   - Resource monitoring
   - Usage tracking

This architecture provides a robust foundation for audit reporting and analytics, ensuring compliance with regulatory requirements while maintaining performance and cost efficiency.

## Data Streaming and Ingestion Architecture

### 1. DynamoDB Stream Configuration

#### DynamoDB Table Setup
```json
{
  "TableName": "audit_events",
  "StreamSpecification": {
    "StreamEnabled": true,
    "StreamViewType": "NEW_AND_OLD_IMAGES"
  },
  "KeySchema": [
    {
      "AttributeName": "event_id",
      "KeyType": "HASH"
    },
    {
      "AttributeName": "timestamp",
      "KeyType": "RANGE"
    }
  ],
  "AttributeDefinitions": [
    {
      "AttributeName": "event_id",
      "AttributeType": "S"
    },
    {
      "AttributeName": "timestamp",
      "AttributeType": "S"
    }
  ]
}
```

#### Stream Processing Lambda
```python
import boto3
import json
import base64

def lambda_handler(event, context):
    kinesis = boto3.client('kinesis')
    
    for record in event['Records']:
        # Decode DynamoDB stream record
        if record['eventName'] == 'INSERT' or record['eventName'] == 'MODIFY':
            new_image = record['dynamodb']['NewImage']
            
            # Transform data for Snowflake compatibility
            transformed_record = {
                'event_id': new_image['event_id']['S'],
                'timestamp': new_image['timestamp']['S'],
                'event_type': new_image['event_type']['S'],
                'user_id': new_image['user_id']['S'],
                'action': new_image['action']['S'],
                'resource_id': new_image['resource_id']['S'],
                'resource_type': new_image['resource_type']['S'],
                'environment': new_image['environment']['S'],
                'region': new_image['region']['S'],
                'metadata': json.dumps(new_image['metadata']['M'])
            }
            
            # Send to Kinesis
            kinesis.put_record(
                StreamName='audit-events-stream',
                Data=json.dumps(transformed_record),
                PartitionKey=transformed_record['event_id']
            )
```

### 2. Kinesis Firehose Configuration

#### Firehose Delivery Stream
```json
{
  "DeliveryStreamName": "audit-events-firehose",
  "DeliveryStreamType": "DirectPut",
  "ExtendedS3DestinationConfiguration": {
    "RoleARN": "arn:aws:iam::123456789012:role/firehose-delivery-role",
    "BucketARN": "arn:aws:s3:::audit-events-bucket",
    "Prefix": "year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
    "ErrorOutputPrefix": "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
    "BufferingHints": {
      "SizeInMBs": 128,
      "IntervalInSeconds": 60
    },
    "CompressionFormat": "GZIP",
    "EncryptionConfiguration": {
      "NoEncryptionConfig": "NoEncryption"
    },
    "CloudWatchLoggingOptions": {
      "Enabled": true,
      "LogGroupName": "/aws/firehose/audit-events",
      "LogStreamName": "delivery-stream"
    }
  }
}
```

### 3. Snowpipe Configuration

#### Storage Integration
```sql
-- Create storage integration for S3
CREATE OR REPLACE STORAGE INTEGRATION s3_audit_events
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-s3-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://audit-events-bucket/');

-- Create file format
CREATE OR REPLACE FILE FORMAT audit_events_json_format
  TYPE = JSON
  COMPRESSION = GZIP
  ENABLE_OCTAL = FALSE
  ALLOW_DUPLICATE = FALSE
  STRIP_OUTER_ARRAY = TRUE;

-- Create stage
CREATE OR REPLACE STAGE audit_events_stage
  URL = 's3://audit-events-bucket/'
  STORAGE_INTEGRATION = s3_audit_events
  FILE_FORMAT = audit_events_json_format;

-- Create pipe
CREATE OR REPLACE PIPE audit_events_pipe
  AUTO_INGEST = TRUE
  AS
  COPY INTO audit_events_raw
  FROM @audit_events_stage
  PATTERN = '.*audit-events-.*.json';
```

### 4. Snowflake Data Mart Setup

#### Raw Data Table
```sql
-- Create raw data table
CREATE OR REPLACE TABLE audit_events_raw (
    event_id VARCHAR,
    timestamp TIMESTAMP,
    event_type VARCHAR,
    user_id VARCHAR,
    action VARCHAR,
    resource_id VARCHAR,
    resource_type VARCHAR,
    environment VARCHAR,
    region VARCHAR,
    metadata VARIANT,
    file_name VARCHAR,
    file_row_number NUMBER,
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Create stream on raw table
CREATE OR REPLACE STREAM audit_events_stream ON TABLE audit_events_raw;
```

#### Data Mart Processing
```sql
-- Create task to process raw data into data marts
CREATE OR REPLACE TASK process_audit_events
  WAREHOUSE = audit_wh
  SCHEDULE = '1 minute'
AS
  MERGE INTO audit_events_mart a
  USING (
    SELECT 
      event_id,
      timestamp,
      event_type,
      user_id,
      action,
      resource_id,
      resource_type,
      environment,
      region,
      metadata
    FROM audit_events_stream
    WHERE metadata IS NOT NULL
  ) s
  ON a.event_id = s.event_id
  WHEN MATCHED THEN
    UPDATE SET
      timestamp = s.timestamp,
      event_type = s.event_type,
      user_id = s.user_id,
      action = s.action,
      resource_id = s.resource_id,
      resource_type = s.resource_type,
      environment = s.environment,
      region = s.region,
      metadata = s.metadata
  WHEN NOT MATCHED THEN
    INSERT (
      event_id,
      timestamp,
      event_type,
      user_id,
      action,
      resource_id,
      resource_type,
      environment,
      region,
      metadata
    )
    VALUES (
      s.event_id,
      s.timestamp,
      s.event_type,
      s.user_id,
      s.action,
      s.resource_id,
      s.resource_type,
      s.environment,
      s.region,
      s.metadata
    );
```

### 5. Design Considerations

#### 1. Data Consistency
- Use DynamoDB streams with NEW_AND_OLD_IMAGES to capture all changes
- Implement idempotency in Lambda processing
- Use Snowflake streams for change data capture
- Implement error handling and dead-letter queues

#### 2. Performance Optimization
- Configure appropriate buffer sizes in Kinesis Firehose
- Use GZIP compression for efficient storage
- Implement partitioning in S3 for better query performance
- Use Snowflake clustering keys for efficient querying

#### 3. Error Handling
```sql
-- Create error logging table
CREATE OR REPLACE TABLE audit_events_errors (
    error_timestamp TIMESTAMP,
    error_type VARCHAR,
    error_message VARCHAR,
    raw_data VARIANT,
    file_name VARCHAR,
    file_row_number NUMBER
);

-- Create error handling procedure
CREATE OR REPLACE PROCEDURE handle_ingestion_errors()
RETURNS STRING
AS
$$
BEGIN
    -- Log errors from copy history
    INSERT INTO audit_events_errors
    SELECT 
        CURRENT_TIMESTAMP(),
        'COPY_ERROR',
        error_message,
        raw_data,
        file_name,
        file_row_number
    FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
        table_name => 'AUDIT_EVENTS_RAW',
        start_time => DATEADD(hours, -1, CURRENT_TIMESTAMP())
    ))
    WHERE error_message IS NOT NULL;
    
    RETURN 'Error handling completed';
END;
$$;
```

#### 4. Monitoring and Alerting
```sql
-- Create monitoring view
CREATE OR REPLACE VIEW vw_ingestion_metrics AS
SELECT 
    DATE_TRUNC('hour', load_timestamp) as hour,
    COUNT(*) as records_processed,
    COUNT(DISTINCT file_name) as files_processed,
    COUNT(CASE WHEN error_message IS NOT NULL THEN 1 END) as error_count
FROM audit_events_raw
GROUP BY 1
ORDER BY 1;

-- Create alert for high error rates
CREATE OR REPLACE ALERT high_error_rate
  WAREHOUSE = audit_wh
  SCHEDULE = '5 minutes'
  IF(EXISTS(
    SELECT 1
    FROM vw_ingestion_metrics
    WHERE hour >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
    AND error_count / records_processed > 0.01
  ))
  THEN
    CALL system$send_email(
      'alerts@company.com',
      'High Error Rate in Audit Events Ingestion',
      'Error rate exceeds 1% in the last hour'
    );
```

#### 5. Cost Optimization
- Implement data retention policies
- Use appropriate warehouse sizes
- Optimize file formats and compression
- Implement efficient clustering strategies

This architecture ensures reliable, scalable, and efficient data streaming from DynamoDB to Snowflake, with proper error handling, monitoring, and cost optimization.

### 6. Streaming Process Monitoring

#### 1. End-to-End Data Flow Monitoring

```sql
-- Create monitoring table for data flow metrics
CREATE OR REPLACE TABLE streaming_metrics (
    metric_timestamp TIMESTAMP,
    source_component VARCHAR,
    target_component VARCHAR,
    record_count NUMBER,
    bytes_processed NUMBER,
    processing_time_ms NUMBER,
    error_count NUMBER,
    latency_ms NUMBER,
    batch_id VARCHAR
);

-- Create view for data flow analysis
CREATE OR REPLACE VIEW vw_data_flow_metrics AS
SELECT 
    DATE_TRUNC('hour', metric_timestamp) as hour,
    source_component,
    target_component,
    SUM(record_count) as total_records,
    SUM(bytes_processed) as total_bytes,
    AVG(processing_time_ms) as avg_processing_time,
    SUM(error_count) as total_errors,
    AVG(latency_ms) as avg_latency,
    COUNT(DISTINCT batch_id) as batch_count
FROM streaming_metrics
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 3;
```

#### 2. Data Loss Detection

```sql
-- Create data consistency check table
CREATE OR REPLACE TABLE data_consistency_checks (
    check_timestamp TIMESTAMP,
    source_count NUMBER,
    target_count NUMBER,
    missing_records NUMBER,
    duplicate_records NUMBER,
    time_window_start TIMESTAMP,
    time_window_end TIMESTAMP,
    check_status VARCHAR
);

-- Create procedure for data consistency check
CREATE OR REPLACE PROCEDURE check_data_consistency()
RETURNS STRING
AS
$$
DECLARE
    window_start TIMESTAMP;
    window_end TIMESTAMP;
    dynamodb_count NUMBER;
    snowflake_count NUMBER;
BEGIN
    -- Set time window for check (last 5 minutes)
    window_start := DATEADD(minute, -5, CURRENT_TIMESTAMP());
    window_end := CURRENT_TIMESTAMP();
    
    -- Get count from DynamoDB (via CloudWatch metrics)
    SELECT metric_value INTO dynamodb_count
    FROM TABLE(INFORMATION_SCHEMA.EXTERNAL_TABLE_FUNCTIONS(
        'dynamodb_metrics',
        'SELECT metric_value FROM dynamodb_metrics WHERE metric_name = \'ConsumedWriteCapacityUnits\''
    ))
    WHERE timestamp BETWEEN window_start AND window_end;
    
    -- Get count from Snowflake
    SELECT COUNT(*) INTO snowflake_count
    FROM audit_events_raw
    WHERE load_timestamp BETWEEN window_start AND window_end;
    
    -- Insert consistency check results
    INSERT INTO data_consistency_checks (
        check_timestamp,
        source_count,
        target_count,
        missing_records,
        duplicate_records,
        time_window_start,
        time_window_end,
        check_status
    )
    SELECT
        CURRENT_TIMESTAMP(),
        dynamodb_count,
        snowflake_count,
        dynamodb_count - snowflake_count,
        (
            SELECT COUNT(*) - COUNT(DISTINCT event_id)
            FROM audit_events_raw
            WHERE load_timestamp BETWEEN window_start AND window_end
        ),
        window_start,
        window_end,
        CASE 
            WHEN dynamodb_count = snowflake_count THEN 'CONSISTENT'
            ELSE 'INCONSISTENT'
        END;
    
    RETURN 'Data consistency check completed';
END;
$$;
```

#### 3. Change Data Capture Monitoring

```sql
-- Create change tracking table
CREATE OR REPLACE TABLE change_tracking (
    tracking_timestamp TIMESTAMP,
    table_name VARCHAR,
    change_type VARCHAR,
    record_count NUMBER,
    change_window_start TIMESTAMP,
    change_window_end TIMESTAMP,
    change_details VARIANT
);

-- Create procedure to track changes
CREATE OR REPLACE PROCEDURE track_data_changes()
RETURNS STRING
AS
$$
BEGIN
    -- Track changes in audit events
    INSERT INTO change_tracking
    SELECT
        CURRENT_TIMESTAMP(),
        'audit_events_mart',
        'CHANGE',
        COUNT(*),
        MIN(timestamp),
        MAX(timestamp),
        OBJECT_CONSTRUCT(
            'inserted', COUNT(CASE WHEN metadata:change_type = 'INSERT' THEN 1 END),
            'updated', COUNT(CASE WHEN metadata:change_type = 'UPDATE' THEN 1 END),
            'deleted', COUNT(CASE WHEN metadata:change_type = 'DELETE' THEN 1 END)
        )
    FROM audit_events_stream
    WHERE timestamp >= DATEADD(minute, -5, CURRENT_TIMESTAMP());
    
    RETURN 'Change tracking completed';
END;
$$;
```

#### 4. Error Monitoring and Alerting

```sql
-- Create comprehensive error monitoring view
CREATE OR REPLACE VIEW vw_error_monitoring AS
SELECT 
    DATE_TRUNC('hour', error_timestamp) as hour,
    error_type,
    COUNT(*) as error_count,
    COUNT(DISTINCT file_name) as affected_files,
    MIN(error_timestamp) as first_error,
    MAX(error_timestamp) as last_error,
    LISTAGG(DISTINCT error_message, '; ') as error_messages
FROM audit_events_errors
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

-- Create error alerting procedure
CREATE OR REPLACE PROCEDURE monitor_errors()
RETURNS STRING
AS
$$
BEGIN
    -- Check for high error rates
    IF EXISTS (
        SELECT 1
        FROM vw_error_monitoring
        WHERE hour >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
        AND error_count > 100
    ) THEN
        CALL system$send_email(
            'alerts@company.com',
            'High Error Rate in Audit Events Processing',
            'Error count exceeds threshold in the last hour'
        );
    END IF;
    
    -- Check for specific error types
    IF EXISTS (
        SELECT 1
        FROM vw_error_monitoring
        WHERE hour >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
        AND error_type = 'DATA_VALIDATION'
        AND error_count > 50
    ) THEN
        CALL system$send_email(
            'data-team@company.com',
            'Data Validation Errors Detected',
            'High number of data validation errors in the last hour'
        );
    END IF;
    
    RETURN 'Error monitoring completed';
END;
$$;
```

#### 5. Performance Monitoring

```sql
-- Create performance monitoring view
CREATE OR REPLACE VIEW vw_performance_metrics AS
SELECT 
    DATE_TRUNC('hour', metric_timestamp) as hour,
    component_name,
    AVG(processing_time_ms) as avg_processing_time,
    MAX(processing_time_ms) as max_processing_time,
    AVG(latency_ms) as avg_latency,
    MAX(latency_ms) as max_latency,
    SUM(record_count) as total_records,
    SUM(bytes_processed) as total_bytes
FROM streaming_metrics
GROUP BY 1, 2
ORDER BY 1 DESC, 2;

-- Create performance alerting procedure
CREATE OR REPLACE PROCEDURE monitor_performance()
RETURNS STRING
AS
$$
BEGIN
    -- Check for high latency
    IF EXISTS (
        SELECT 1
        FROM vw_performance_metrics
        WHERE hour >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
        AND avg_latency > 5000  -- 5 seconds
    ) THEN
        CALL system$send_email(
            'performance-team@company.com',
            'High Latency in Audit Events Processing',
            'Average latency exceeds 5 seconds in the last hour'
        );
    END IF;
    
    -- Check for processing time spikes
    IF EXISTS (
        SELECT 1
        FROM vw_performance_metrics
        WHERE hour >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
        AND max_processing_time > 10000  -- 10 seconds
    ) THEN
        CALL system$send_email(
            'performance-team@company.com',
            'Processing Time Spikes Detected',
            'Maximum processing time exceeds 10 seconds in the last hour'
        );
    END IF;
    
    RETURN 'Performance monitoring completed';
END;
$$;
```

#### 6. Monitoring Dashboard Queries

```sql
-- Create dashboard view for overall health
CREATE OR REPLACE VIEW vw_streaming_health AS
SELECT
    DATE_TRUNC('hour', CURRENT_TIMESTAMP()) as current_hour,
    (SELECT COUNT(*) FROM audit_events_raw 
     WHERE load_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())) as records_processed,
    (SELECT COUNT(*) FROM audit_events_errors 
     WHERE error_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())) as error_count,
    (SELECT AVG(latency_ms) FROM streaming_metrics 
     WHERE metric_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())) as avg_latency,
    (SELECT COUNT(*) FROM data_consistency_checks 
     WHERE check_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
     AND check_status = 'INCONSISTENT') as consistency_issues,
    (SELECT COUNT(DISTINCT batch_id) FROM streaming_metrics 
     WHERE metric_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())) as batch_count;

-- Create trend analysis view
CREATE OR REPLACE VIEW vw_streaming_trends AS
SELECT
    DATE_TRUNC('day', metric_timestamp) as day,
    AVG(record_count) as avg_daily_records,
    AVG(error_count) as avg_daily_errors,
    AVG(latency_ms) as avg_daily_latency,
    MAX(processing_time_ms) as max_processing_time,
    COUNT(DISTINCT batch_id) as daily_batches
FROM streaming_metrics
GROUP BY 1
ORDER BY 1 DESC;
```

This monitoring architecture provides comprehensive visibility into the streaming process, enabling:
- Detection of data loss through consistency checks
- Tracking of data changes through CDC monitoring
- Identification of errors through detailed error tracking
- Performance monitoring through latency and processing time metrics
- Trend analysis through historical data collection
- Proactive alerting for issues that require attention

The monitoring system is designed to be:
- Real-time: Provides immediate visibility into current operations
- Comprehensive: Covers all aspects of the streaming process
- Actionable: Includes specific alerts and notifications
- Historical: Maintains trend data for analysis
- Scalable: Can handle increasing data volumes