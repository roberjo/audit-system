using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace AuditQuery.Tests.Load
{
    /// <summary>
    /// Load tests for the audit query service.
    /// Tests system performance under concurrent load and pagination scenarios.
    /// </summary>
    public class AuditQueryLoadTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDb;
        private readonly string _tableName;
        private readonly ILogger<AuditQueryLoadTests> _logger;
        private readonly AuditQueryService _queryService;

        /// <summary>
        /// Initializes the load test environment with DynamoDB client and test table.
        /// </summary>
        public AuditQueryLoadTests(ITestOutputHelper output)
        {
            _dynamoDb = new AmazonDynamoDBClient();
            _tableName = $"audit-query-load-test-{Guid.NewGuid()}";
            _logger = new LoggerFactory()
                .AddXUnit(output)
                .CreateLogger<AuditQueryLoadTests>();
            _queryService = new AuditQueryService(_dynamoDb, _logger);
        }

        /// <summary>
        /// Sets up the test environment by creating a DynamoDB table and inserting test data.
        /// </summary>
        public async Task InitializeAsync()
        {
            // Create test table with appropriate schema
            var createTableRequest = new Amazon.DynamoDBv2.Model.CreateTableRequest
            {
                TableName = _tableName,
                KeySchema = new List<Amazon.DynamoDBv2.Model.KeySchemaElement>
                {
                    new Amazon.DynamoDBv2.Model.KeySchemaElement
                    {
                        AttributeName = "userId",
                        KeyType = "HASH"
                    },
                    new Amazon.DynamoDBv2.Model.KeySchemaElement
                    {
                        AttributeName = "timestamp",
                        KeyType = "RANGE"
                    }
                },
                AttributeDefinitions = new List<Amazon.DynamoDBv2.Model.AttributeDefinition>
                {
                    new Amazon.DynamoDBv2.Model.AttributeDefinition
                    {
                        AttributeName = "userId",
                        AttributeType = "S"
                    },
                    new Amazon.DynamoDBv2.Model.AttributeDefinition
                    {
                        AttributeName = "timestamp",
                        AttributeType = "S"
                    }
                },
                ProvisionedThroughput = new Amazon.DynamoDBv2.Model.ProvisionedThroughput
                {
                    ReadCapacityUnits = 100,
                    WriteCapacityUnits = 100
                }
            };

            await _dynamoDb.CreateTableAsync(createTableRequest);

            // Insert test data in batches for better performance
            var table = Table.LoadTable(_dynamoDb, _tableName);
            var batchWrite = table.CreateBatchWrite();
            var random = new Random();

            for (int i = 0; i < 1000; i++)
            {
                var doc = new Document
                {
                    ["userId"] = $"user{random.Next(1, 11)}",
                    ["timestamp"] = DateTime.UtcNow.AddMinutes(-random.Next(0, 60)).ToString("o"),
                    ["action"] = $"action{random.Next(1, 6)}",
                    ["systemId"] = $"system{random.Next(1, 4)}",
                    ["details"] = $"Test details {i}"
                };
                batchWrite.AddDocumentToPut(doc);

                if (i % 25 == 0)
                {
                    await batchWrite.ExecuteAsync();
                    batchWrite = table.CreateBatchWrite();
                }
            }

            if (batchWrite.PendingPutItems.Count > 0)
            {
                await batchWrite.ExecuteAsync();
            }
        }

        /// <summary>
        /// Cleans up test resources by deleting the test table.
        /// </summary>
        public async Task DisposeAsync()
        {
            await _dynamoDb.DeleteTableAsync(_tableName);
        }

        /// <summary>
        /// Tests system performance under concurrent query load.
        /// Executes multiple queries simultaneously to verify system stability.
        /// </summary>
        [Fact]
        public async Task LoadTest_ConcurrentQueries()
        {
            const int concurrentQueries = 50;
            const int iterations = 10;
            var totalTime = 0L;
            var random = new Random();

            for (int i = 0; i < iterations; i++)
            {
                var startTime = DateTime.UtcNow;
                var tasks = new List<Task>();

                // Execute concurrent queries with different parameters
                for (int j = 0; j < concurrentQueries; j++)
                {
                    var userId = $"user{random.Next(1, 11)}";
                    var systemId = $"system{random.Next(1, 4)}";
                    tasks.Add(ExecuteQuery(userId, systemId));
                }

                await Task.WhenAll(tasks);
                totalTime += (long)(DateTime.UtcNow - startTime).TotalMilliseconds;
            }

            var averageTime = totalTime / iterations;
            _logger.LogInformation($"Average time for {concurrentQueries} concurrent queries: {averageTime}ms");
            Assert.True(averageTime < 5000, $"Average query time {averageTime}ms exceeds 5 second threshold");
        }

        /// <summary>
        /// Tests pagination performance by retrieving large result sets in pages.
        /// Verifies system behavior with large data volumes.
        /// </summary>
        [Fact]
        public async Task LoadTest_Pagination()
        {
            const int pageSize = 100;
            var startTime = DateTime.UtcNow;
            var totalItems = 0;
            string? lastEvaluatedKey = null;

            // Retrieve all records using pagination
            do
            {
                var result = await _queryService.QueryAuditRecordsAsync(
                    userId: "user1",
                    pageSize: pageSize,
                    lastEvaluatedKey: lastEvaluatedKey);

                totalItems += result.Items.Count;
                lastEvaluatedKey = result.LastEvaluatedKey;
            } while (lastEvaluatedKey != null);

            var totalTime = (long)(DateTime.UtcNow - startTime).TotalMilliseconds;
            var averageTimePerPage = totalTime / (totalItems / pageSize);

            _logger.LogInformation($"Retrieved {totalItems} items in {totalTime}ms");
            _logger.LogInformation($"Average time per page: {averageTimePerPage}ms");
            Assert.True(averageTimePerPage < 1000, $"Average page retrieval time {averageTimePerPage}ms exceeds 1 second threshold");
        }

        /// <summary>
        /// Helper method to execute a single query with error handling.
        /// </summary>
        private async Task ExecuteQuery(string userId, string systemId)
        {
            try
            {
                await _queryService.QueryAuditRecordsAsync(
                    userId: userId,
                    systemId: systemId,
                    pageSize: 50);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error executing query for user {userId} and system {systemId}");
                throw;
            }
        }
    }
} 