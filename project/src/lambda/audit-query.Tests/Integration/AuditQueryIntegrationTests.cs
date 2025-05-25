using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.DynamoDBv2.Model;
using Microsoft.Extensions.Logging;
using Xunit;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace AuditQuery.Tests.Integration
{
    public class AuditQueryIntegrationTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDbClient;
        private readonly string _tableName;
        private readonly AuditQueryService _service;
        private readonly ILogger<AuditQueryService> _logger;

        public AuditQueryIntegrationTests()
        {
            _dynamoDbClient = new AmazonDynamoDBClient();
            _tableName = $"test-audit-table-{Guid.NewGuid()}";
            _logger = LoggerFactory.Create(builder => builder.AddConsole())
                .CreateLogger<AuditQueryService>();
            _service = new AuditQueryService(_dynamoDbClient, _tableName, _logger);
        }

        public async Task InitializeAsync()
        {
            // Create test table
            var createTableRequest = new CreateTableRequest
            {
                TableName = _tableName,
                AttributeDefinitions = new List<AttributeDefinition>
                {
                    new AttributeDefinition
                    {
                        AttributeName = "userId",
                        AttributeType = ScalarAttributeType.S
                    },
                    new AttributeDefinition
                    {
                        AttributeName = "timestamp",
                        AttributeType = ScalarAttributeType.S
                    }
                },
                KeySchema = new List<KeySchemaElement>
                {
                    new KeySchemaElement
                    {
                        AttributeName = "userId",
                        KeyType = KeyType.HASH
                    },
                    new KeySchemaElement
                    {
                        AttributeName = "timestamp",
                        KeyType = KeyType.RANGE
                    }
                },
                ProvisionedThroughput = new ProvisionedThroughput
                {
                    ReadCapacityUnits = 5,
                    WriteCapacityUnits = 5
                }
            };

            await _dynamoDbClient.CreateTableAsync(createTableRequest);

            // Wait for table to become active
            var describeTableRequest = new DescribeTableRequest { TableName = _tableName };
            while (true)
            {
                var response = await _dynamoDbClient.DescribeTableAsync(describeTableRequest);
                if (response.Table.TableStatus == TableStatus.ACTIVE)
                    break;
                await Task.Delay(1000);
            }

            // Insert test data
            var testData = new List<Document>
            {
                new Document
                {
                    ["userId"] = "test-user-1",
                    ["timestamp"] = DateTime.UtcNow.AddHours(-2).ToString("o"),
                    ["action"] = "test-action-1",
                    ["systemId"] = "test-system-1"
                },
                new Document
                {
                    ["userId"] = "test-user-1",
                    ["timestamp"] = DateTime.UtcNow.AddHours(-1).ToString("o"),
                    ["action"] = "test-action-2",
                    ["systemId"] = "test-system-1"
                },
                new Document
                {
                    ["userId"] = "test-user-2",
                    ["timestamp"] = DateTime.UtcNow.ToString("o"),
                    ["action"] = "test-action-3",
                    ["systemId"] = "test-system-2"
                }
            };

            var table = Table.LoadTable(_dynamoDbClient, _tableName);
            foreach (var item in testData)
            {
                await table.PutItemAsync(item);
            }
        }

        public async Task DisposeAsync()
        {
            // Delete test table
            await _dynamoDbClient.DeleteTableAsync(_tableName);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithUserId_ShouldReturnMatchingRecords()
        {
            // Act
            var result = await _service.QueryAuditRecordsAsync(userId: "test-user-1");

            // Assert
            Assert.NotNull(result);
            Assert.Equal(2, result.Items.Count);
            Assert.All(result.Items, item => Assert.Equal("test-user-1", item["userId"]));
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithDateRange_ShouldReturnMatchingRecords()
        {
            // Arrange
            var startDate = DateTime.UtcNow.AddHours(-3);
            var endDate = DateTime.UtcNow.AddHours(-1);

            // Act
            var result = await _service.QueryAuditRecordsAsync(
                userId: "test-user-1",
                startDate: startDate,
                endDate: endDate);

            // Assert
            Assert.NotNull(result);
            Assert.Single(result.Items);
            Assert.Equal("test-action-1", result.Items[0]["action"]);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithSystemId_ShouldReturnMatchingRecords()
        {
            // Act
            var result = await _service.QueryAuditRecordsAsync(systemId: "test-system-2");

            // Assert
            Assert.NotNull(result);
            Assert.Single(result.Items);
            Assert.Equal("test-system-2", result.Items[0]["systemId"]);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithPagination_ShouldReturnCorrectPage()
        {
            // Act
            var result = await _service.QueryAuditRecordsAsync(
                userId: "test-user-1",
                pageSize: 1);

            // Assert
            Assert.NotNull(result);
            Assert.Single(result.Items);
            Assert.NotNull(result.LastEvaluatedKey);
        }
    }
} 