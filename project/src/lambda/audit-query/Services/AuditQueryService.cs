using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DocumentModel;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace AuditQuery.Services;

public class AuditQueryService : IAuditQueryService
{
    private readonly IAmazonDynamoDB _dynamoDb;
    private readonly string _tableName;
    private readonly ILogger<AuditQueryService> _logger;

    public AuditQueryService(
        IAmazonDynamoDB dynamoDb,
        string tableName,
        ILogger<AuditQueryService> logger)
    {
        _dynamoDb = dynamoDb ?? throw new ArgumentNullException(nameof(dynamoDb));
        _tableName = tableName ?? throw new ArgumentNullException(nameof(tableName));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public async Task<QueryResult> QueryAuditRecordsAsync(QueryParameters parameters)
    {
        try
        {
            var table = Table.LoadTable(_dynamoDb, _tableName);
            var query = BuildQuery(table, parameters);
            var result = await query.GetNextSetAsync();

            return new QueryResult
            {
                Items = result,
                LastEvaluatedKey = query.LastEvaluatedKey
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error querying audit records");
            throw;
        }
    }

    private QueryOperationConfig BuildQuery(Table table, QueryParameters parameters)
    {
        var queryConfig = new QueryOperationConfig
        {
            Filter = new QueryFilter("timestamp", QueryOperator.Between, parameters.StartDate, parameters.EndDate),
            Limit = parameters.PageSize,
            Select = SelectValues.AllAttributes
        };

        if (!string.IsNullOrEmpty(parameters.LastEvaluatedKey))
        {
            queryConfig.ExclusiveStartKey = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, AttributeValue>>(parameters.LastEvaluatedKey);
        }

        if (!string.IsNullOrEmpty(parameters.UserId) && !string.IsNullOrEmpty(parameters.SystemId))
        {
            // Query using GSI with both userId and systemId
            queryConfig.IndexName = "AuditIndex";
            queryConfig.KeyExpression = new Expression
            {
                ExpressionStatement = "userId = :userId",
                ExpressionAttributeValues = new Dictionary<string, DynamoDBEntry>
                {
                    { ":userId", parameters.UserId }
                }
            };
            queryConfig.Filter.ExpressionStatement += " AND systemId = :systemId";
            queryConfig.Filter.ExpressionAttributeValues[":systemId"] = parameters.SystemId;
        }
        else if (!string.IsNullOrEmpty(parameters.UserId))
        {
            // Query using GSI with userId
            queryConfig.IndexName = "AuditIndex";
            queryConfig.KeyExpression = new Expression
            {
                ExpressionStatement = "userId = :userId",
                ExpressionAttributeValues = new Dictionary<string, DynamoDBEntry>
                {
                    { ":userId", parameters.UserId }
                }
            };
        }
        else if (!string.IsNullOrEmpty(parameters.SystemId))
        {
            // Query using LSI with systemId
            queryConfig.IndexName = "SystemIndex";
            queryConfig.KeyExpression = new Expression
            {
                ExpressionStatement = "systemId = :systemId",
                ExpressionAttributeValues = new Dictionary<string, DynamoDBEntry>
                {
                    { ":systemId", parameters.SystemId }
                }
            };
        }

        return queryConfig;
    }
} 