using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using Amazon.DynamoDBv2.Model;
using AuditQuery.Exceptions;
using AuditQuery.Models;
using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace AuditQuery.Services;

public class AuditQueryService : IAuditQueryService
{
    private readonly IAmazonDynamoDB _dynamoDbClient;
    private readonly string _tableName;
    private readonly ILogger<AuditQueryService> _logger;

    public AuditQueryService(
        IAmazonDynamoDB dynamoDbClient,
        string tableName,
        ILogger<AuditQueryService> logger)
    {
        _dynamoDbClient = dynamoDbClient ?? throw new ArgumentNullException(nameof(dynamoDbClient));
        _tableName = tableName ?? throw new ArgumentNullException(nameof(tableName));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public async Task<QueryResult> QueryAuditRecordsAsync(
        string? userId = null,
        string? systemId = null,
        DateTime? startDate = null,
        DateTime? endDate = null,
        int pageSize = 50,
        Dictionary<string, AttributeValue>? lastEvaluatedKey = null)
    {
        try
        {
            var parameters = new QueryParameters
            {
                UserId = userId,
                SystemId = systemId,
                StartDate = startDate,
                EndDate = endDate,
                PageSize = pageSize,
                LastEvaluatedKey = lastEvaluatedKey
            };

            parameters.Validate();

            var queryRequest = BuildQuery(parameters);

            try
            {
                var response = await _dynamoDbClient.QueryAsync(queryRequest);
                return new QueryResult
                {
                    Items = response.Items.Select(item => Document.FromAttributeMap(item)).ToList(),
                    LastEvaluatedKey = response.LastEvaluatedKey
                };
            }
            catch (AmazonDynamoDBException ex)
            {
                _logger.LogError(ex, "Error querying DynamoDB table {TableName}", _tableName);
                throw new DynamoDbQueryException(
                    $"Failed to query audit records: {ex.Message}",
                    ex);
            }
        }
        catch (InvalidQueryParametersException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error in QueryAuditRecordsAsync");
            throw new AuditQueryException(
                "An unexpected error occurred while querying audit records",
                ex);
        }
    }

    private QueryRequest BuildQuery(QueryParameters parameters)
    {
        var request = new QueryRequest
        {
            TableName = _tableName,
            Limit = parameters.PageSize,
            ExclusiveStartKey = parameters.LastEvaluatedKey
        };

        var expressions = new List<string>();
        var expressionValues = new Dictionary<string, AttributeValue>();

        if (!string.IsNullOrEmpty(parameters.UserId))
        {
            expressions.Add("userId = :userId");
            expressionValues[":userId"] = new AttributeValue { S = parameters.UserId };
        }

        if (!string.IsNullOrEmpty(parameters.SystemId))
        {
            expressions.Add("systemId = :systemId");
            expressionValues[":systemId"] = new AttributeValue { S = parameters.SystemId };
        }

        if (parameters.StartDate.HasValue && parameters.EndDate.HasValue)
        {
            expressions.Add("timestamp BETWEEN :startDate AND :endDate");
            expressionValues[":startDate"] = new AttributeValue 
            { 
                S = parameters.StartDate.Value.ToString("o") 
            };
            expressionValues[":endDate"] = new AttributeValue 
            { 
                S = parameters.EndDate.Value.ToString("o") 
            };
        }

        if (expressions.Any())
        {
            request.KeyConditionExpression = string.Join(" AND ", expressions);
            request.ExpressionAttributeValues = expressionValues;
        }

        return request;
    }
} 