# Audit Query API Documentation

## Overview

The Audit Query API provides a RESTful interface to query audit records stored in DynamoDB. It supports querying by user ID, system ID, or both, with date range filtering and pagination capabilities.

## Base URL

```
https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/query
```

## Authentication

Currently, the API endpoint is configured without authentication. In production environments, it's recommended to implement proper authentication mechanisms.

## API Endpoints

### Query Audit Records

Retrieves audit records based on specified criteria.

**Endpoint:** `POST /query`

#### Request Body

```json
{
  "userId": "string",        // Optional: Filter by user ID
  "systemId": "string",      // Optional: Filter by system ID
  "startDate": "string",     // Required: Start date in ISO 8601 format
  "endDate": "string",       // Required: End date in ISO 8601 format
  "pageSize": number,        // Optional: Number of items per page (default: 20)
  "lastEvaluatedKey": "string" // Optional: Pagination token for next page
}
```

#### Date Format

Dates should be provided in ISO 8601 format:
```
YYYY-MM-DDThh:mm:ssZ
```

Example: `2024-01-01T00:00:00Z`

#### Response

```json
{
  "items": [
    {
      "id": "string",
      "userId": "string",
      "systemId": "string",
      "dataBefore": {
        // Previous state of the data
      },
      "dataAfter": {
        // New state of the data
      },
      "timestamp": "string"
    }
  ],
  "lastEvaluatedKey": "string" // Present if more results are available
}
```

#### Status Codes

- `200 OK`: Request successful
- `400 Bad Request`: Invalid query parameters
- `500 Internal Server Error`: Server-side error

## Query Examples

### 1. Query by User ID

```json
{
  "userId": "user123",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-01-31T23:59:59Z",
  "pageSize": 20
}
```

### 2. Query by System ID

```json
{
  "systemId": "system456",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-01-31T23:59:59Z",
  "pageSize": 20
}
```

### 3. Query by Both User ID and System ID

```json
{
  "userId": "user123",
  "systemId": "system456",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-01-31T23:59:59Z",
  "pageSize": 20
}
```

## Pagination

The API implements pagination using DynamoDB's LastEvaluatedKey mechanism:

1. Initial request: Omit `lastEvaluatedKey`
2. Subsequent requests: Include the `lastEvaluatedKey` from the previous response
3. No more results: Response will not include `lastEvaluatedKey`

Example pagination flow:

```json
// First request
{
  "userId": "user123",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-01-31T23:59:59Z",
  "pageSize": 20
}

// Response
{
  "items": [...],
  "lastEvaluatedKey": "eyJpZCI6eyJTIjoiZXhhbXBsZSJ9LCJ0aW1lc3RhbXAiOnsiUyI6IjIwMjQtMDEtMDFUMDA6MDA6MDBaIn19"
}

// Next request
{
  "userId": "user123",
  "startDate": "2024-01-01T00:00:00Z",
  "endDate": "2024-01-31T23:59:59Z",
  "pageSize": 20,
  "lastEvaluatedKey": "eyJpZCI6eyJTIjoiZXhhbXBsZSJ9LCJ0aW1lc3RhbXAiOnsiUyI6IjIwMjQtMDEtMDFUMDA6MDA6MDBaIn19"
}
```

## Performance Considerations

1. **Index Usage**:
   - User ID queries use the Global Secondary Index (GSI)
   - System ID queries use the Local Secondary Index (LSI)
   - Combined queries use GSI with additional filtering

2. **Query Optimization**:
   - Always include date range filters
   - Use appropriate page size (default: 20)
   - Consider using smaller date ranges for better performance

3. **Rate Limiting**:
   - Default DynamoDB read capacity is shared across all queries
   - Monitor CloudWatch metrics for throttling

## Error Handling

### Common Error Scenarios

1. **Invalid Date Format**
```json
{
  "error": "Invalid query parameters"
}
```

2. **Missing Required Parameters**
```json
{
  "error": "Invalid query parameters"
}
```

3. **Server Error**
```json
{
  "error": "Internal server error"
}
```

## Monitoring

The API is integrated with CloudWatch for monitoring:

1. **Metrics**:
   - Request count
   - Latency
   - Error rates
   - Throttled requests

2. **Logs**:
   - Query parameters
   - Execution time
   - Error details

## Best Practices

1. **Query Optimization**:
   - Use specific date ranges
   - Implement client-side caching
   - Use appropriate page sizes

2. **Error Handling**:
   - Implement retry logic for 500 errors
   - Validate dates before sending
   - Handle pagination properly

3. **Security**:
   - Validate input parameters
   - Implement proper authentication
   - Use HTTPS

## Rate Limits

- Default DynamoDB read capacity units apply
- Monitor CloudWatch metrics for throttling
- Implement exponential backoff for retries

## Support

For issues or questions, contact the system administrators or raise an issue in the project repository. 