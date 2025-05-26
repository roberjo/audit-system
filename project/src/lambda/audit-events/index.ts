import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { v4 as uuidv4 } from 'uuid';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';

const client = new DynamoDBClient({});
const dynamoDB = DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.DYNAMODB_TABLE ?? '';

interface AuditEvent {
  id: string;
  timestamp: string;
  eventType: string;
  userId: string;
  action: string;
  resource: string;
  details: Record<string, any>;
  metadata: {
    ipAddress: string;
    userAgent: string;
    environment: string;
  };
}

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  try {
    if (!event.body) {
      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Request body is required' }),
      };
    }

    const requestBody = JSON.parse(event.body);
    const auditEvent: AuditEvent = {
      id: uuidv4(),
      timestamp: new Date().toISOString(),
      eventType: requestBody.eventType,
      userId: requestBody.userId,
      action: requestBody.action,
      resource: requestBody.resource,
      details: requestBody.details || {},
      metadata: {
        ipAddress: event.requestContext.identity.sourceIp,
        userAgent: event.requestContext.identity.userAgent ?? '',
        environment: process.env.ENVIRONMENT ?? 'dev',
      },
    };

    // Validate required fields
    if (!auditEvent.eventType || !auditEvent.userId || !auditEvent.action || !auditEvent.resource) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          message: 'Missing required fields: eventType, userId, action, resource',
        }),
      };
    }

    // Store event in DynamoDB
    await dynamoDB.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: auditEvent,
      })
    );

    return {
      statusCode: 201,
      body: JSON.stringify({
        message: 'Audit event recorded successfully',
        eventId: auditEvent.id,
      }),
    };
  } catch (error) {
    console.error('Error processing audit event:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Internal server error',
        error: error instanceof Error ? error.message : 'Unknown error',
      }),
    };
  }
}; 