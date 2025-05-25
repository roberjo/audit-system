using Amazon.Lambda.APIGatewayEvents;
using Amazon.Lambda.Core;
using Amazon.DynamoDBv2;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using AuditQuery.Services;
using AuditQuery.Models;
using System.Text.Json.Serialization;

namespace AuditQuery;

public class Function
{
    private readonly IAuditQueryService _queryService;
    private readonly ILogger<Function> _logger;

    public Function()
    {
        var services = ConfigureServices();
        _queryService = services.GetRequiredService<IAuditQueryService>();
        _logger = services.GetRequiredService<ILogger<Function>>();
    }

    private static IServiceProvider ConfigureServices()
    {
        var services = new ServiceCollection();

        // Add AWS Services
        services.AddAWSService<IAmazonDynamoDB>();
        services.AddSingleton(Environment.GetEnvironmentVariable("DYNAMODB_TABLE") ?? 
            throw new InvalidOperationException("DYNAMODB_TABLE environment variable is not set"));

        // Add Application Services
        services.AddScoped<IAuditQueryService, AuditQueryService>();

        // Add Logging
        services.AddLogging(builder =>
        {
            builder.AddLambdaLogger();
            builder.SetMinimumLevel(LogLevel.Information);
        });

        return services.BuildServiceProvider();
    }

    public async Task<APIGatewayProxyResponse> FunctionHandler(APIGatewayProxyRequest request, ILambdaContext context)
    {
        try
        {
            var queryParams = JsonSerializer.Deserialize<QueryParameters>(request.Body);
            if (queryParams == null)
            {
                _logger.LogWarning("Invalid query parameters received");
                return new APIGatewayProxyResponse
                {
                    StatusCode = 400,
                    Body = JsonSerializer.Serialize(new { error = "Invalid query parameters" })
                };
            }

            var result = await _queryService.QueryAuditRecordsAsync(queryParams);

            return new APIGatewayProxyResponse
            {
                StatusCode = 200,
                Body = JsonSerializer.Serialize(new
                {
                    items = result.Items,
                    lastEvaluatedKey = result.LastEvaluatedKey
                })
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing request");
            return new APIGatewayProxyResponse
            {
                StatusCode = 500,
                Body = JsonSerializer.Serialize(new { error = "Internal server error" })
            };
        }
    }
}

public class QueryParameters
{
    [JsonPropertyName("userId")]
    public string? UserId { get; set; }

    [JsonPropertyName("systemId")]
    public string? SystemId { get; set; }

    [JsonPropertyName("startDate")]
    public string StartDate { get; set; } = string.Empty;

    [JsonPropertyName("endDate")]
    public string EndDate { get; set; } = string.Empty;

    [JsonPropertyName("pageSize")]
    public int PageSize { get; set; } = 20;

    [JsonPropertyName("lastEvaluatedKey")]
    public string? LastEvaluatedKey { get; set; }
} 