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
    /// <summary>
    /// Security tests for the audit query service.
    /// Tests various security vulnerabilities and input validation scenarios.
    /// </summary>
    public class AuditQuerySecurityTests : IAsyncLifetime
    {
        private readonly IAmazonDynamoDB _dynamoDb;
        private readonly string _tableName;
        private readonly ILogger<AuditQuerySecurityTests> _logger;
        private readonly AuditQueryService _queryService;

        /// <summary>
        /// Initializes the security test environment with DynamoDB client and test table.
        /// </summary>
        public AuditQuerySecurityTests(ITestOutputHelper output)
        {
            _dynamoDb = new AmazonDynamoDBClient();
            _tableName = $"audit-query-security-test-{Guid.NewGuid()}";
            _logger = new LoggerFactory()
                .AddXUnit(output)
                .CreateLogger<AuditQuerySecurityTests>();
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

            // Insert test document with sensitive data
            var table = Table.LoadTable(_dynamoDb, _tableName);
            var doc = new Document
            {
                ["userId"] = "testuser",
                ["timestamp"] = DateTime.UtcNow.ToString("o"),
                ["action"] = "login",
                ["systemId"] = "testsystem",
                ["sensitiveData"] = "secret123"
            };
            await table.PutItemAsync(doc);
        }

        /// <summary>
        /// Cleans up test resources by deleting the test table.
        /// </summary>
        public async Task DisposeAsync()
        {
            await _dynamoDb.DeleteTableAsync(_tableName);
        }

        /// <summary>
        /// Tests SQL injection prevention in query parameters.
        /// Verifies that malicious SQL-like input is properly sanitized.
        /// </summary>
        [Fact]
        public async Task SecurityTest_SQLInjection()
        {
            // Test SQL injection in userId
            var result1 = await _queryService.QueryAuditRecordsAsync(
                userId: "testuser' OR '1'='1",
                pageSize: 10);
            Assert.Empty(result1.Items);

            // Test SQL injection in systemId
            var result2 = await _queryService.QueryAuditRecordsAsync(
                userId: "testuser",
                systemId: "testsystem' OR '1'='1",
                pageSize: 10);
            Assert.Empty(result2.Items);
        }

        /// <summary>
        /// Tests NoSQL injection prevention in query parameters.
        /// Verifies that malicious NoSQL-like input is properly sanitized.
        /// </summary>
        [Fact]
        public async Task SecurityTest_NoSQLInjection()
        {
            // Test NoSQL injection in userId
            var result1 = await _queryService.QueryAuditRecordsAsync(
                userId: "testuser\" : { \"$gt\": \"\" }",
                pageSize: 10);
            Assert.Empty(result1.Items);

            // Test NoSQL injection in systemId
            var result2 = await _queryService.QueryAuditRecordsAsync(
                userId: "testuser",
                systemId: "testsystem\" : { \"$gt\": \"\" }",
                pageSize: 10);
            Assert.Empty(result2.Items);
        }

        /// <summary>
        /// Tests data exposure prevention.
        /// Verifies that sensitive data is not exposed in query results.
        /// </summary>
        [Fact]
        public async Task SecurityTest_DataExposure()
        {
            var result = await _queryService.QueryAuditRecordsAsync(
                userId: "testuser",
                pageSize: 10);

            Assert.Single(result.Items);
            Assert.DoesNotContain("sensitiveData", result.Items[0].Keys);
        }

        /// <summary>
        /// Tests input validation for various parameters.
        /// Verifies that invalid input is properly rejected.
        /// </summary>
        [Fact]
        public async Task SecurityTest_InputValidation()
        {
            // Test extremely long userId
            await Assert.ThrowsAsync<InvalidQueryParametersException>(() =>
                _queryService.QueryAuditRecordsAsync(
                    userId: new string('a', 1001),
                    pageSize: 10));

            // Test invalid date range
            await Assert.ThrowsAsync<InvalidQueryParametersException>(() =>
                _queryService.QueryAuditRecordsAsync(
                    userId: "testuser",
                    startDate: DateTime.UtcNow,
                    endDate: DateTime.UtcNow.AddDays(-1),
                    pageSize: 10));

            // Test invalid page size
            await Assert.ThrowsAsync<InvalidQueryParametersException>(() =>
                _queryService.QueryAuditRecordsAsync(
                    userId: "testuser",
                    pageSize: 1001));
        }

        /// <summary>
        /// Tests resource exhaustion prevention.
        /// Verifies that the system handles large requests without crashing.
        /// </summary>
        [Fact]
        public async Task SecurityTest_ResourceExhaustion()
        {
            // Test with very large page size
            var result = await _queryService.QueryAuditRecordsAsync(
                userId: "testuser",
                pageSize: 999);

            Assert.NotNull(result);
            Assert.True(result.Items.Count <= 1000);
        }
    }
} 