using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.DynamoDBv2.Model;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace AuditQuery.Tests
{
    public class AuditQueryServiceTests
    {
        private readonly Mock<IAmazonDynamoDB> _mockDynamoDbClient;
        private readonly Mock<ILogger<AuditQueryService>> _mockLogger;
        private readonly string _tableName = "test-audit-table";
        private readonly AuditQueryService _service;

        public AuditQueryServiceTests()
        {
            _mockDynamoDbClient = new Mock<IAmazonDynamoDB>();
            _mockLogger = new Mock<ILogger<AuditQueryService>>();
            _service = new AuditQueryService(_mockDynamoDbClient.Object, _tableName, _mockLogger.Object);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithUserId_ShouldQueryCorrectly()
        {
            // Arrange
            var userId = "test-user";
            var expectedItems = new List<Document>
            {
                new Document
                {
                    ["userId"] = userId,
                    ["timestamp"] = DateTime.UtcNow.ToString("o"),
                    ["action"] = "test-action"
                }
            };

            _mockDynamoDbClient
                .Setup(x => x.QueryAsync(It.IsAny<QueryRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new QueryResponse
                {
                    Items = new List<Dictionary<string, AttributeValue>>
                    {
                        new Dictionary<string, AttributeValue>
                        {
                            ["userId"] = new AttributeValue { S = userId },
                            ["timestamp"] = new AttributeValue { S = DateTime.UtcNow.ToString("o") },
                            ["action"] = new AttributeValue { S = "test-action" }
                        }
                    }
                });

            // Act
            var result = await _service.QueryAuditRecordsAsync(userId: userId);

            // Assert
            Assert.NotNull(result);
            Assert.Single(result.Items);
            Assert.Equal(userId, result.Items[0]["userId"]);
            _mockDynamoDbClient.Verify(x => x.QueryAsync(
                It.Is<QueryRequest>(req => 
                    req.TableName == _tableName &&
                    req.KeyConditionExpression == "userId = :userId"),
                It.IsAny<CancellationToken>()),
                Times.Once);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithDateRange_ShouldQueryCorrectly()
        {
            // Arrange
            var startDate = DateTime.UtcNow.AddDays(-1);
            var endDate = DateTime.UtcNow;
            var expectedItems = new List<Document>
            {
                new Document
                {
                    ["userId"] = "test-user",
                    ["timestamp"] = DateTime.UtcNow.ToString("o"),
                    ["action"] = "test-action"
                }
            };

            _mockDynamoDbClient
                .Setup(x => x.QueryAsync(It.IsAny<QueryRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new QueryResponse
                {
                    Items = new List<Dictionary<string, AttributeValue>>
                    {
                        new Dictionary<string, AttributeValue>
                        {
                            ["userId"] = new AttributeValue { S = "test-user" },
                            ["timestamp"] = new AttributeValue { S = DateTime.UtcNow.ToString("o") },
                            ["action"] = new AttributeValue { S = "test-action" }
                        }
                    }
                });

            // Act
            var result = await _service.QueryAuditRecordsAsync(
                startDate: startDate,
                endDate: endDate);

            // Assert
            Assert.NotNull(result);
            Assert.Single(result.Items);
            _mockDynamoDbClient.Verify(x => x.QueryAsync(
                It.Is<QueryRequest>(req => 
                    req.TableName == _tableName &&
                    req.FilterExpression.Contains("timestamp BETWEEN :startDate AND :endDate")),
                It.IsAny<CancellationToken>()),
                Times.Once);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WithPagination_ShouldHandleCorrectly()
        {
            // Arrange
            var lastEvaluatedKey = new Dictionary<string, AttributeValue>
            {
                ["userId"] = new AttributeValue { S = "test-user" },
                ["timestamp"] = new AttributeValue { S = DateTime.UtcNow.ToString("o") }
            };

            _mockDynamoDbClient
                .Setup(x => x.QueryAsync(It.IsAny<QueryRequest>(), It.IsAny<CancellationToken>()))
                .ReturnsAsync(new QueryResponse
                {
                    Items = new List<Dictionary<string, AttributeValue>>(),
                    LastEvaluatedKey = lastEvaluatedKey
                });

            // Act
            var result = await _service.QueryAuditRecordsAsync(
                lastEvaluatedKey: lastEvaluatedKey);

            // Assert
            Assert.NotNull(result);
            Assert.Empty(result.Items);
            Assert.NotNull(result.LastEvaluatedKey);
            _mockDynamoDbClient.Verify(x => x.QueryAsync(
                It.Is<QueryRequest>(req => 
                    req.TableName == _tableName &&
                    req.ExclusiveStartKey == lastEvaluatedKey),
                It.IsAny<CancellationToken>()),
                Times.Once);
        }

        [Fact]
        public async Task QueryAuditRecordsAsync_WhenDynamoDbThrowsException_ShouldLogAndRethrow()
        {
            // Arrange
            var expectedException = new AmazonDynamoDBException("Test exception");
            _mockDynamoDbClient
                .Setup(x => x.QueryAsync(It.IsAny<QueryRequest>(), It.IsAny<CancellationToken>()))
                .ThrowsAsync(expectedException);

            // Act & Assert
            var exception = await Assert.ThrowsAsync<AmazonDynamoDBException>(
                () => _service.QueryAuditRecordsAsync());

            Assert.Equal(expectedException, exception);
            _mockLogger.Verify(
                x => x.Log(
                    LogLevel.Error,
                    It.IsAny<EventId>(),
                    It.Is<It.IsAnyType>((v, t) => true),
                    It.IsAny<Exception>(),
                    It.Is<Func<It.IsAnyType, Exception, string>>((v, t) => true)),
                Times.Once);
        }
    }
} 