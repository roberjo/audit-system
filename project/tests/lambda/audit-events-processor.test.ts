import { SQSEvent, Context } from 'aws-lambda';
import { handler } from '../../src/lambda/audit-events-processor';
import { DynamoDB } from 'aws-sdk';

// Mock AWS SDK
jest.mock('aws-sdk', () => {
  const mockPut = jest.fn().mockReturnValue({
    promise: jest.fn().mockResolvedValue({})
  });

  const mockDocumentClient = jest.fn(() => ({
    put: mockPut
  }));

  return {
    DynamoDB: {
      DocumentClient: mockDocumentClient
    }
  };
});

describe('Audit Events Processor Lambda', () => {
  let mockEvent: SQSEvent;
  let mockContext: Context;

  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();

    // Setup mock event
    mockEvent = {
      Records: [
        {
          messageId: 'test-message-id',
          body: JSON.stringify({
            Message: JSON.stringify({
              userId: 'test-user',
              systemId: 'test-system',
              dataBefore: { key: 'old-value' },
              dataAfter: { key: 'new-value' },
              timestamp: '2024-01-01T00:00:00Z'
            })
          }),
          attributes: {
            ApproximateReceiveCount: '1',
            SentTimestamp: '1234567890',
            SenderId: 'test-sender',
            ApproximateFirstReceiveTimestamp: '1234567890'
          },
          messageAttributes: {},
          md5OfBody: 'test-md5',
          eventSource: 'aws:sqs',
          eventSourceARN: 'arn:aws:sqs:us-east-1:123456789012:test-queue',
          awsRegion: 'us-east-1'
        }
      ]
    };

    // Setup mock context
    mockContext = {
      callbackWaitsForEmptyEventLoop: true,
      functionName: 'test-function',
      functionVersion: '1',
      invokedFunctionArn: 'arn:aws:lambda:us-east-1:123456789012:function:test-function',
      memoryLimitInMB: '128',
      awsRequestId: 'test-request-id',
      logGroupName: 'test-log-group',
      logStreamName: 'test-log-stream',
      getRemainingTimeInMillis: () => 1000,
      done: () => {},
      fail: () => {},
      succeed: () => {}
    };
  });

  it('should process valid audit event successfully', async () => {
    // Set environment variable
    process.env.DYNAMODB_TABLE = 'test-table';

    // Execute handler
    await handler(mockEvent, mockContext);

    // Verify DynamoDB put was called with correct parameters
    const dynamoDB = new DynamoDB.DocumentClient();
    expect(dynamoDB.put).toHaveBeenCalledWith(expect.objectContaining({
      TableName: 'test-table',
      Item: expect.objectContaining({
        userId: 'test-user',
        systemId: 'test-system',
        dataBefore: { key: 'old-value' },
        dataAfter: { key: 'new-value' },
        timestamp: '2024-01-01T00:00:00Z'
      })
    }));
  });

  it('should throw error for missing required fields', async () => {
    // Setup event with missing required fields
    mockEvent.Records[0].body = JSON.stringify({
      Message: JSON.stringify({
        userId: 'test-user',
        // Missing systemId
        dataBefore: { key: 'old-value' },
        dataAfter: { key: 'new-value' }
      })
    });

    // Execute handler and expect error
    await expect(handler(mockEvent, mockContext)).rejects.toThrow('Missing required fields: userId and systemId are required');
  });

  it('should process multiple records in parallel', async () => {
    // Add multiple records to the event
    mockEvent.Records.push({
      ...mockEvent.Records[0],
      messageId: 'test-message-id-2',
      body: JSON.stringify({
        Message: JSON.stringify({
          userId: 'test-user-2',
          systemId: 'test-system-2',
          dataBefore: { key: 'old-value-2' },
          dataAfter: { key: 'new-value-2' },
          timestamp: '2024-01-01T00:00:00Z'
        })
      })
    });

    // Execute handler
    await handler(mockEvent, mockContext);

    // Verify DynamoDB put was called twice
    const dynamoDB = new DynamoDB.DocumentClient();
    expect(dynamoDB.put).toHaveBeenCalledTimes(2);
  });
}); 