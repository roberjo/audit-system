"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
const aws_sdk_1 = require("aws-sdk");
const uuid_1 = require("uuid");
const dynamoDB = new aws_sdk_1.DynamoDB.DocumentClient();
const TABLE_NAME = process.env.DYNAMODB_TABLE || '';
function logQueryMetrics(metrics) {
    console.log(JSON.stringify({
        ...metrics,
        timestamp: new Date().toISOString()
    }));
}
async function processRecord(record) {
    const startTime = Date.now();
    try {
        const messageBody = JSON.parse(record.body);
        const snsMessage = JSON.parse(messageBody.Message);
        // Calculate TTL (30 days from now)
        const ttl = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);
        const auditEvent = {
            id: (0, uuid_1.v4)(),
            userId: snsMessage.userId,
            systemId: snsMessage.systemId,
            dataBefore: snsMessage.dataBefore || {},
            dataAfter: snsMessage.dataAfter || {},
            timestamp: snsMessage.timestamp || new Date().toISOString(),
            ttl: snsMessage.ttl || ttl
        };
        // Validate required fields
        if (!auditEvent.userId || !auditEvent.systemId) {
            throw new Error('Missing required fields: userId and systemId are required');
        }
        // Save to DynamoDB
        const params = {
            TableName: TABLE_NAME,
            Item: {
                ...auditEvent,
                ttl: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60) // 1 year TTL
            }
        };
        await dynamoDB.put(params).promise();
        const endTime = Date.now();
        const duration = endTime - startTime;
        // Log individual record processing metrics
        logQueryMetrics({
            startTime,
            endTime,
            duration,
            operation: 'PutItem',
            tableName: TABLE_NAME,
            queryParams: params
        });
        console.log(`Successfully processed audit event: ${auditEvent.id}`);
    }
    catch (error) {
        console.error('Error processing record:', error);
        throw error;
    }
}
const handler = async (event, context) => {
    const startTime = Date.now();
    console.log('Processing SQS event:', JSON.stringify(event));
    try {
        // Process records in parallel
        await Promise.all(event.Records.map(processRecord));
    }
    catch (error) {
        console.error('Error processing SQS event:', error);
        throw error;
    }
    const endTime = Date.now();
    const duration = endTime - startTime;
    // Log overall batch processing metrics
    logQueryMetrics({
        startTime,
        endTime,
        duration,
        operation: 'BatchProcess',
        tableName: TABLE_NAME,
        queryParams: {
            recordCount: event.Records.length
        }
    });
};
exports.handler = handler;
//# sourceMappingURL=index.js.map