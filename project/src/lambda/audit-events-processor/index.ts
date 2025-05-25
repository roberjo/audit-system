import { SQSEvent, SQSRecord, Context } from 'aws-lambda';
import { DynamoDB } from 'aws-sdk';
import { v4 as uuidv4 } from 'uuid';
import { AuditEvent } from './types';

const dynamoDB = new DynamoDB.DocumentClient();
const TABLE_NAME = process.env.DYNAMODB_TABLE || '';

interface QueryMetrics {
  startTime: number;
  endTime: number;
  duration: number;
  operation: string;
  tableName: string;
  queryParams: any;
}

function logQueryMetrics(metrics: QueryMetrics): void {
  console.log(JSON.stringify({
    ...metrics,
    timestamp: new Date().toISOString()
  }));
}

async function processRecord(record: SQSRecord): Promise<void> {
  const startTime = Date.now();
  try {
    const messageBody = JSON.parse(record.body);
    const snsMessage = JSON.parse(messageBody.Message);
    
    // Calculate TTL (30 days from now)
    const ttl = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);
    
    const auditEvent: AuditEvent = {
      id: uuidv4(),
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
  } catch (error) {
    console.error('Error processing record:', error);
    throw error;
  }
}

export const handler = async (event: SQSEvent, context: Context): Promise<void> => {
  const startTime = Date.now();
  console.log('Processing SQS event:', JSON.stringify(event));

  try {
    // Process records in parallel
    await Promise.all(event.Records.map(processRecord));
  } catch (error) {
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