using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace AuditQuery.Tests.Chaos
{
    /// <summary>
    /// Chaos tests for the audit query service.
    /// Tests system resilience under various failure scenarios and edge cases.
    /// </summary>
    public class AuditQueryChaosTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDb;
        private readonly string _tableName;
        private readonly ILogger<AuditQueryChaosTests> _logger;
        private readonly AuditQueryService _queryService;

        /// <summary>
        /// Initializes the chaos test environment with DynamoDB client and test table.
        /// </summary>
        public AuditQueryChaosTests(ITestOutputHelper output)
        {
            _dynamoDb = new AmazonDynamoDBClient();
            _tableName = $"audit-query-chaos-test-{Guid.NewGuid()}";
            _logger = new LoggerFactory()
                .AddXUnit(output)
                .CreateLogger<AuditQueryChaosTests>();
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
                    ReadCapacityUnits = 5,
                    WriteCapacityUnits = 5
                }
            };

            await _dynamoDb.CreateTableAsync(createTableRequest);

            // Insert test data in batches
            var table = Table.LoadTable(_dynamoDb, _tableName);
            var batchWrite = table.CreateBatchWrite();
            var random = new Random();

            for (int i = 0; i < 100; i++)
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
        /// Tests system stability under concurrent query load.
        /// Verifies that the system maintains stability with multiple simultaneous requests.
        /// </summary>
        [Fact]
        public async Task ChaosTest_ConcurrentQueries()
        {
            const int concurrentQueries = 100;
            var tasks = new List<Task>();
            var errors = 0;
            var random = new Random();

            // Execute concurrent queries with random parameters
            for (int i = 0; i < concurrentQueries; i++)
            {
                var userId = $"user{random.Next(1, 11)}";
                var systemId = $"system{random.Next(1, 4)}";
                tasks.Add(ExecuteQuery(userId, systemId, ref errors));
            }

            await Task.WhenAll(tasks);
            var errorRate = (double)errors / concurrentQueries;
            _logger.LogInformation($"Error rate: {errorRate:P2}");

            Assert.True(errorRate < 0.1, $"Error rate {errorRate:P2} exceeds 10% threshold");
        }

        /// <summary>
        /// Tests system behavior under rapid pagination requests.
        /// Verifies that the system handles rapid page requests without degradation.
        /// </summary>
        [Fact]
        public async Task ChaosTest_RapidPagination()
        {
            const int iterations = 50;
            var errors = 0;
            var random = new Random();

            // Execute rapid pagination requests
            for (int i = 0; i < iterations; i++)
            {
                var userId = $"user{random.Next(1, 11)}";
                var pageSize = random.Next(10, 100);
                await ExecutePagination(userId, pageSize, ref errors);
            }

            var errorRate = (double)errors / iterations;
            _logger.LogInformation($"Error rate: {errorRate:P2}");

            Assert.True(errorRate < 0.1, $"Error rate {errorRate:P2} exceeds 10% threshold");
        }

        /// <summary>
        /// Tests system handling of invalid parameters.
        /// Verifies that the system gracefully handles invalid input without crashing.
        /// </summary>
        [Fact]
        public async Task ChaosTest_InvalidParameters()
        {
            const int iterations = 100;
            var errors = 0;
            var random = new Random();

            // Test various invalid parameter combinations
            for (int i = 0; i < iterations; i++)
            {
                var userId = random.Next(2) == 0 ? null : new string('a', random.Next(1, 1001));
                var systemId = random.Next(2) == 0 ? null : new string('a', random.Next(1, 1001));
                var pageSize = random.Next(-100, 1001);

                try
                {
                    await _queryService.QueryAuditRecordsAsync(
                        userId: userId,
                        systemId: systemId,
                        pageSize: pageSize);
                }
                catch (Exception ex)
                {
                    errors++;
                    _logger.LogWarning(ex, "Expected error with invalid parameters");
                }
            }

            // Some errors are expected with invalid parameters
            Assert.True(errors > 0, "No errors occurred with invalid parameters");
        }

        /// <summary>
        /// Tests system stability during concurrent table updates and queries.
        /// Verifies that the system maintains consistency during concurrent operations.
        /// </summary>
        [Fact]
        public async Task ChaosTest_TableUpdates()
        {
            const int iterations = 50;
            var errors = 0;
            var random = new Random();
            var table = Table.LoadTable(_dynamoDb, _tableName);

            // Execute concurrent updates and queries
            for (int i = 0; i < iterations; i++)
            {
                var tasks = new List<Task>();

                // Add update task
                tasks.Add(UpdateTable(table, random, ref errors));

                // Add query tasks
                for (int j = 0; j < 5; j++)
                {
                    var userId = $"user{random.Next(1, 11)}";
                    var systemId = $"system{random.Next(1, 4)}";
                    tasks.Add(ExecuteQuery(userId, systemId, ref errors));
                }

                await Task.WhenAll(tasks);
            }

            var errorRate = (double)errors / (iterations * 6);
            _logger.LogInformation($"Error rate: {errorRate:P2}");

            Assert.True(errorRate < 0.1, $"Error rate {errorRate:P2} exceeds 10% threshold");
        }

        /// <summary>
        /// Helper method to execute a single query with error tracking.
        /// </summary>
        private async Task ExecuteQuery(string userId, string systemId, ref int errors)
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
                errors++;
                _logger.LogError(ex, $"Error executing query for user {userId} and system {systemId}");
            }
        }

        /// <summary>
        /// Helper method to execute pagination with error tracking.
        /// </summary>
        private async Task ExecutePagination(string userId, int pageSize, ref int errors)
        {
            try
            {
                string? lastEvaluatedKey = null;
                do
                {
                    var result = await _queryService.QueryAuditRecordsAsync(
                        userId: userId,
                        pageSize: pageSize,
                        lastEvaluatedKey: lastEvaluatedKey);

                    lastEvaluatedKey = result.LastEvaluatedKey;
                } while (lastEvaluatedKey != null);
            }
            catch (Exception ex)
            {
                errors++;
                _logger.LogError(ex, $"Error executing pagination for user {userId}");
            }
        }

        /// <summary>
        /// Helper method to update the test table with error tracking.
        /// </summary>
        private async Task UpdateTable(Table table, Random random, ref int errors)
        {
            try
            {
                var doc = new Document
                {
                    ["userId"] = $"user{random.Next(1, 11)}",
                    ["timestamp"] = DateTime.UtcNow.ToString("o"),
                    ["action"] = $"action{random.Next(1, 6)}",
                    ["systemId"] = $"system{random.Next(1, 4)}",
                    ["details"] = $"Update details {random.Next(1000)}"
                };
                await table.PutItemAsync(doc);
            }
            catch (Exception ex)
            {
                errors++;
                _logger.LogError(ex, "Error updating table");
            }
        }
    }
} 