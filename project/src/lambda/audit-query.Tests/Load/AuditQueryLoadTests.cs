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
    public class AuditQueryLoadTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDbClient;
        private readonly string _tableName;
        private readonly AuditQueryService _service;
        private readonly ILogger<AuditQueryService> _logger;
        private readonly ITestOutputHelper _output;

        public AuditQueryLoadTests(ITestOutputHelper output)
        {
            _dynamoDbClient = new AmazonDynamoDBClient();
            _tableName = $"load-test-audit-table-{Guid.NewGuid()}";
            _logger = LoggerFactory.Create(builder => builder.AddConsole())
                .CreateLogger<AuditQueryService>();
            _service = new AuditQueryService(_dynamoDbClient, _tableName, _logger);
            _output = output;
        }

        public async Task InitializeAsync()
        {
            // Create test table with higher capacity
            var createTableRequest = new Amazon.DynamoDBv2.Model.CreateTableRequest
            {
                TableName = _tableName,
                AttributeDefinitions = new List<Amazon.DynamoDBv2.Model.AttributeDefinition>
                {
                    new Amazon.DynamoDBv2.Model.AttributeDefinition
                    {
                        AttributeName = "userId",
                        AttributeType = Amazon.DynamoDBv2.ScalarAttributeType.S
                    },
                    new Amazon.DynamoDBv2.Model.AttributeDefinition
                    {
                        AttributeName = "timestamp",
                        AttributeType = Amazon.DynamoDBv2.ScalarAttributeType.S
                    }
                },
                KeySchema = new List<Amazon.DynamoDBv2.Model.KeySchemaElement>
                {
                    new Amazon.DynamoDBv2.Model.KeySchemaElement
                    {
                        AttributeName = "userId",
                        KeyType = Amazon.DynamoDBv2.KeyType.HASH
                    },
                    new Amazon.DynamoDBv2.Model.KeySchemaElement
                    {
                        AttributeName = "timestamp",
                        KeyType = Amazon.DynamoDBv2.KeyType.RANGE
                    }
                },
                ProvisionedThroughput = new Amazon.DynamoDBv2.Model.ProvisionedThroughput
                {
                    ReadCapacityUnits = 100,
                    WriteCapacityUnits = 100
                }
            };

            await _dynamoDbClient.CreateTableAsync(createTableRequest);

            // Wait for table to become active
            var describeTableRequest = new Amazon.DynamoDBv2.Model.DescribeTableRequest { TableName = _tableName };
            while (true)
            {
                var response = await _dynamoDbClient.DescribeTableAsync(describeTableRequest);
                if (response.Table.TableStatus == Amazon.DynamoDBv2.TableStatus.ACTIVE)
                    break;
                await Task.Delay(1000);
            }

            // Insert test data
            var table = Table.LoadTable(_dynamoDbClient, _tableName);
            var tasks = new List<Task>();

            for (int i = 0; i < 1000; i++)
            {
                var document = new Document
                {
                    ["userId"] = $"user-{i % 100}",
                    ["timestamp"] = DateTime.UtcNow.AddHours(-i).ToString("o"),
                    ["action"] = $"action-{i % 10}",
                    ["systemId"] = $"system-{i % 5}"
                };

                tasks.Add(table.PutItemAsync(document));

                if (tasks.Count >= 25)
                {
                    await Task.WhenAll(tasks);
                    tasks.Clear();
                }
            }

            if (tasks.Any())
            {
                await Task.WhenAll(tasks);
            }
        }

        public async Task DisposeAsync()
        {
            await _dynamoDbClient.DeleteTableAsync(_tableName);
        }

        [Fact]
        public async Task LoadTest_ConcurrentQueries()
        {
            const int concurrentQueries = 50;
            const int iterations = 10;

            var tasks = new List<Task>();
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();

            for (int i = 0; i < iterations; i++)
            {
                for (int j = 0; j < concurrentQueries; j++)
                {
                    tasks.Add(ExecuteQuery($"user-{j % 100}"));
                }

                await Task.WhenAll(tasks);
                tasks.Clear();
            }

            stopwatch.Stop();
            var totalQueries = concurrentQueries * iterations;
            var averageTime = stopwatch.ElapsedMilliseconds / totalQueries;

            _output.WriteLine($"Executed {totalQueries} queries in {stopwatch.ElapsedMilliseconds}ms");
            _output.WriteLine($"Average query time: {averageTime}ms");
        }

        [Fact]
        public async Task LoadTest_Pagination()
        {
            const int pageSize = 100;
            const int expectedPages = 10;

            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            var totalItems = 0;
            Dictionary<string, Amazon.DynamoDBv2.Model.AttributeValue>? lastEvaluatedKey = null;

            for (int i = 0; i < expectedPages; i++)
            {
                var result = await _service.QueryAuditRecordsAsync(
                    userId: "user-0",
                    pageSize: pageSize,
                    lastEvaluatedKey: lastEvaluatedKey);

                totalItems += result.Items.Count;
                lastEvaluatedKey = result.LastEvaluatedKey;

                if (lastEvaluatedKey == null)
                    break;
            }

            stopwatch.Stop();
            var averageTime = stopwatch.ElapsedMilliseconds / expectedPages;

            _output.WriteLine($"Retrieved {totalItems} items in {expectedPages} pages");
            _output.WriteLine($"Average page retrieval time: {averageTime}ms");
        }

        private async Task ExecuteQuery(string userId)
        {
            try
            {
                var result = await _service.QueryAuditRecordsAsync(userId: userId);
                Assert.NotNull(result);
            }
            catch (Exception ex)
            {
                _output.WriteLine($"Error executing query for user {userId}: {ex.Message}");
                throw;
            }
        }
    }
} 