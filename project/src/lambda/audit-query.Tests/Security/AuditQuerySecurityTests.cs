using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;

namespace AuditQuery.Tests.Security
{
    public class AuditQuerySecurityTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDbClient;
        private readonly string _tableName;
        private readonly AuditQueryService _service;
        private readonly ILogger<AuditQueryService> _logger;
        private readonly ITestOutputHelper _output;

        public AuditQuerySecurityTests(ITestOutputHelper output)
        {
            _dynamoDbClient = new AmazonDynamoDBClient();
            _tableName = $"security-test-audit-table-{Guid.NewGuid()}";
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
            var document = new Document
            {
                ["userId"] = "test-user",
                ["timestamp"] = DateTime.UtcNow.ToString("o"),
                ["action"] = "test-action",
                ["systemId"] = "test-system",
                ["sensitiveData"] = "sensitive-value"
            };

            await table.PutItemAsync(document);
        }

        public async Task DisposeAsync()
        {
            await _dynamoDbClient.DeleteTableAsync(_tableName);
        }

        [Fact]
        public async Task SecurityTest_SQLInjection()
        {
            // Test for SQL injection in userId
            var maliciousUserId = "test-user' OR '1'='1";
            var result = await _service.QueryAuditRecordsAsync(userId: maliciousUserId);
            Assert.Empty(result.Items);

            // Test for SQL injection in systemId
            var maliciousSystemId = "test-system' OR '1'='1";
            result = await _service.QueryAuditRecordsAsync(systemId: maliciousSystemId);
            Assert.Empty(result.Items);
        }

        [Fact]
        public async Task SecurityTest_NoSQLInjection()
        {
            // Test for NoSQL injection in userId
            var maliciousUserId = "test-user\" || \"1\"==\"1";
            var result = await _service.QueryAuditRecordsAsync(userId: maliciousUserId);
            Assert.Empty(result.Items);

            // Test for NoSQL injection in systemId
            var maliciousSystemId = "test-system\" || \"1\"==\"1";
            result = await _service.QueryAuditRecordsAsync(systemId: maliciousSystemId);
            Assert.Empty(result.Items);
        }

        [Fact]
        public async Task SecurityTest_DataExposure()
        {
            // Test that sensitive data is not exposed
            var result = await _service.QueryAuditRecordsAsync(userId: "test-user");
            Assert.Single(result.Items);
            Assert.False(result.Items[0].ContainsKey("sensitiveData"));
        }

        [Fact]
        public async Task SecurityTest_InputValidation()
        {
            // Test extremely long userId
            var longUserId = new string('a', 1000);
            await Assert.ThrowsAsync<InvalidQueryParametersException>(
                () => _service.QueryAuditRecordsAsync(userId: longUserId));

            // Test invalid date range
            var futureDate = DateTime.UtcNow.AddYears(1);
            var pastDate = DateTime.UtcNow.AddYears(-1);
            await Assert.ThrowsAsync<InvalidQueryParametersException>(
                () => _service.QueryAuditRecordsAsync(
                    userId: "test-user",
                    startDate: futureDate,
                    endDate: pastDate));

            // Test invalid page size
            await Assert.ThrowsAsync<InvalidQueryParametersException>(
                () => _service.QueryAuditRecordsAsync(
                    userId: "test-user",
                    pageSize: 0));

            await Assert.ThrowsAsync<InvalidQueryParametersException>(
                () => _service.QueryAuditRecordsAsync(
                    userId: "test-user",
                    pageSize: 1001));
        }

        [Fact]
        public async Task SecurityTest_ResourceExhaustion()
        {
            // Test with very large page size
            var result = await _service.QueryAuditRecordsAsync(
                userId: "test-user",
                pageSize: 1000);

            // Should not throw an exception but limit results
            Assert.True(result.Items.Count <= 1000);
        }
    }
} 