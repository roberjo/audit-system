import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { DynamoDB } from 'aws-sdk';
import { v4 as uuidv4 } from 'uuid';

const dynamoDB = new DynamoDB.DocumentClient();
const TABLE_NAME = process.env.DYNAMODB_TABLE || '';

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
        userAgent: event.requestContext.identity.userAgent || '',
        environment: process.env.ENVIRONMENT || 'dev',
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
    await dynamoDB
      .put({
        TableName: TABLE_NAME,
        Item: auditEvent,
      })
      .promise();

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