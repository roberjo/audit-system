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
    public class AuditQueryChaosTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDbClient;
        private readonly string _tableName;
        private readonly AuditQueryService _service;
        private readonly ILogger<AuditQueryService> _logger;
        private readonly ITestOutputHelper _output;

        public AuditQueryChaosTests(ITestOutputHelper output)
        {
            _dynamoDbClient = new AmazonDynamoDBClient();
            _tableName = $"chaos-test-audit-table-{Guid.NewGuid()}";
            _logger = LoggerFactory.Create(builder => builder.AddConsole())
                .CreateLogger<AuditQueryService>();
            _service = new AuditQueryService(_dynamoDbClient, _tableName, _logger);
            _output = output;
        }

        public async Task InitializeAsync()
        {
            // Create test table
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
                    ReadCapacityUnits = 5,
                    WriteCapacityUnits = 5
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

            for (int i = 0; i < 100; i++)
            {
                var document = new Document
                {
                    ["userId"] = $"user-{i % 10}",
                    ["timestamp"] = DateTime.UtcNow.AddHours(-i).ToString("o"),
                    ["action"] = $"action-{i % 5}",
                    ["systemId"] = $"system-{i % 3}"
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
        public async Task ChaosTest_ConcurrentQueries()
        {
            const int concurrentQueries = 100;
            var tasks = new List<Task>();
            var errors = 0;

            for (int i = 0; i < concurrentQueries; i++)
            {
                tasks.Add(Task.Run(async () =>
                {
                    try
                    {
                        var result = await _service.QueryAuditRecordsAsync(
                            userId: $"user-{i % 10}",
                            pageSize: 10);
                        Assert.NotNull(result);
                    }
                    catch (Exception ex)
                    {
                        _output.WriteLine($"Error in concurrent query: {ex.Message}");
                        errors++;
                    }
                }));
            }

            await Task.WhenAll(tasks);
            _output.WriteLine($"Completed {concurrentQueries} concurrent queries with {errors} errors");
            Assert.True(errors < concurrentQueries * 0.1); // Allow up to 10% error rate
        }

        [Fact]
        public async Task ChaosTest_RapidPagination()
        {
            const int iterations = 50;
            var errors = 0;
            Dictionary<string, Amazon.DynamoDBv2.Model.AttributeValue>? lastEvaluatedKey = null;

            for (int i = 0; i < iterations; i++)
            {
                try
                {
                    var result = await _service.QueryAuditRecordsAsync(
                        userId: "user-0",
                        pageSize: 10,
                        lastEvaluatedKey: lastEvaluatedKey);

                    lastEvaluatedKey = result.LastEvaluatedKey;
                    if (lastEvaluatedKey == null)
                        break;
                }
                catch (Exception ex)
                {
                    _output.WriteLine($"Error in pagination: {ex.Message}");
                    errors++;
                }
            }

            _output.WriteLine($"Completed {iterations} pagination requests with {errors} errors");
            Assert.True(errors < iterations * 0.1); // Allow up to 10% error rate
        }

        [Fact]
        public async Task ChaosTest_InvalidParameters()
        {
            const int iterations = 100;
            var errors = 0;

            for (int i = 0; i < iterations; i++)
            {
                try
                {
                    // Randomly generate invalid parameters
                    var random = new Random();
                    var userId = random.Next(2) == 0 ? null : $"user-{random.Next(10)}";
                    var systemId = random.Next(2) == 0 ? null : $"system-{random.Next(3)}";
                    var startDate = random.Next(2) == 0 ? null : DateTime.UtcNow.AddDays(random.Next(-10, 10));
                    var endDate = random.Next(2) == 0 ? null : DateTime.UtcNow.AddDays(random.Next(-10, 10));
                    var pageSize = random.Next(2) == 0 ? random.Next(-100, 0) : random.Next(1001, 2000);

                    var result = await _service.QueryAuditRecordsAsync(
                        userId: userId,
                        systemId: systemId,
                        startDate: startDate,
                        endDate: endDate,
                        pageSize: pageSize);

                    Assert.NotNull(result);
                }
                catch (Exception ex)
                {
                    _output.WriteLine($"Error with invalid parameters: {ex.Message}");
                    errors++;
                }
            }

            _output.WriteLine($"Completed {iterations} invalid parameter tests with {errors} errors");
            Assert.True(errors > 0); // Should have some errors with invalid parameters
        }

        [Fact]
        public async Task ChaosTest_TableUpdates()
        {
            const int iterations = 50;
            var errors = 0;
            var table = Table.LoadTable(_dynamoDbClient, _tableName);

            for (int i = 0; i < iterations; i++)
            {
                try
                {
                    // Update table while querying
                    var updateTask = Task.Run(async () =>
                    {
                        var document = new Document
                        {
                            ["userId"] = $"user-{i % 10}",
                            ["timestamp"] = DateTime.UtcNow.ToString("o"),
                            ["action"] = $"action-{i % 5}",
                            ["systemId"] = $"system-{i % 3}"
                        };

                        await table.PutItemAsync(document);
                    });

                    var queryTask = Task.Run(async () =>
                    {
                        var result = await _service.QueryAuditRecordsAsync(
                            userId: $"user-{i % 10}",
                            pageSize: 10);
                        Assert.NotNull(result);
                    });

                    await Task.WhenAll(updateTask, queryTask);
                }
                catch (Exception ex)
                {
                    _output.WriteLine($"Error during table updates: {ex.Message}");
                    errors++;
                }
            }

            _output.WriteLine($"Completed {iterations} concurrent updates and queries with {errors} errors");
            Assert.True(errors < iterations * 0.1); // Allow up to 10% error rate
        }
    }
} 