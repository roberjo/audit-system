using Amazon.Lambda.APIGatewayEvents;
using AuditQuery.Exceptions;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace AuditQuery.Middleware
{
    public class RequestValidationMiddleware
    {
        private readonly ILogger<RequestValidationMiddleware> _logger;
        private readonly string _apiKey;
        private readonly int _maxRequestsPerMinute;

        public RequestValidationMiddleware(
            ILogger<RequestValidationMiddleware> logger,
            string apiKey,
            int maxRequestsPerMinute = 100)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _apiKey = apiKey ?? throw new ArgumentNullException(nameof(apiKey));
            _maxRequestsPerMinute = maxRequestsPerMinute;
        }

        public async Task<APIGatewayProxyResponse> ValidateRequest(
            APIGatewayProxyRequest request,
            Func<APIGatewayProxyRequest, Task<APIGatewayProxyResponse>> next)
        {
            try
            {
                // Validate API key
                if (!ValidateApiKey(request))
                {
                    _logger.LogWarning("Invalid API key in request");
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 401,
                        Body = "Invalid API key"
                    };
                }

                // Validate rate limit
                if (!await ValidateRateLimit(request))
                {
                    _logger.LogWarning("Rate limit exceeded for request");
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 429,
                        Body = "Rate limit exceeded"
                    };
                }

                // Validate query parameters
                if (!ValidateQueryParameters(request))
                {
                    _logger.LogWarning("Invalid query parameters in request");
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 400,
                        Body = "Invalid query parameters"
                    };
                }

                return await next(request);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error validating request");
                return new APIGatewayProxyResponse
                {
                    StatusCode = 500,
                    Body = "Internal server error"
                };
            }
        }

        private bool ValidateApiKey(APIGatewayProxyRequest request)
        {
            if (!request.Headers.TryGetValue("X-API-Key", out var requestApiKey))
            {
                return false;
            }

            return requestApiKey == _apiKey;
        }

        private async Task<bool> ValidateRateLimit(APIGatewayProxyRequest request)
        {
            // TODO: Implement rate limiting using DynamoDB or Redis
            // For now, return true to allow all requests
            return true;
        }

        private bool ValidateQueryParameters(APIGatewayProxyRequest request)
        {
            if (request.QueryStringParameters == null)
            {
                return true;
            }

            // Validate page size
            if (request.QueryStringParameters.TryGetValue("pageSize", out var pageSizeStr))
            {
                if (!int.TryParse(pageSizeStr, out var pageSize) || pageSize < 1 || pageSize > 1000)
                {
                    return false;
                }
            }

            // Validate dates
            if (request.QueryStringParameters.TryGetValue("startDate", out var startDateStr) &&
                request.QueryStringParameters.TryGetValue("endDate", out var endDateStr))
            {
                if (!DateTime.TryParse(startDateStr, out var startDate) ||
                    !DateTime.TryParse(endDateStr, out var endDate) ||
                    startDate > endDate)
                {
                    return false;
                }
            }

            return true;
        }
    }
} 