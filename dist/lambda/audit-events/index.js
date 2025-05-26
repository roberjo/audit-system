"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const uuid_1 = require("uuid");
const client_dynamodb_1 = require("@aws-sdk/client-dynamodb");
const lib_dynamodb_1 = require("@aws-sdk/lib-dynamodb");
const client = new client_dynamodb_1.DynamoDBClient({});
const dynamoDB = lib_dynamodb_1.DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.DYNAMODB_TABLE || '';
const handler = async (event) => {
    try {
        if (!event.body) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: 'Request body is required' }),
            };
        }
        const requestBody = JSON.parse(event.body);
        const auditEvent = {
            id: (0, uuid_1.v4)(),
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
        await dynamoDB.send(new lib_dynamodb_1.PutCommand({
            TableName: TABLE_NAME,
            Item: auditEvent,
        }));
        return {
            statusCode: 201,
            body: JSON.stringify({
                message: 'Audit event recorded successfully',
                eventId: auditEvent.id,
            }),
        };
    }
    catch (error) {
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
exports.handler = handler;
//# sourceMappingURL=index.js.map