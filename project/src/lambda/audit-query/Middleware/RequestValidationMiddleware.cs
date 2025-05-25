using Amazon.Lambda.APIGatewayEvents;
using AuditQuery.Exceptions;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace AuditQuery.Middleware
{
    /// <summary>
    /// Middleware for validating API requests, implementing rate limiting, and API key validation.
    /// This middleware acts as a security and validation layer before requests reach the main handler.
    /// </summary>
    public class RequestValidationMiddleware
    {
        private readonly ILogger<RequestValidationMiddleware> _logger;
        private readonly string _apiKey;
        private readonly int _maxRequestsPerMinute;

        /// <summary>
        /// Initializes the middleware with required dependencies and configuration.
        /// </summary>
        /// <param name="logger">Logger for tracking validation events and errors</param>
        /// <param name="apiKey">API key for request authentication</param>
        /// <param name="maxRequestsPerMinute">Rate limit threshold</param>
        public RequestValidationMiddleware(
            ILogger<RequestValidationMiddleware> logger,
            string apiKey,
            int maxRequestsPerMinute = 100)
        {
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _apiKey = apiKey ?? throw new ArgumentNullException(nameof(apiKey));
            _maxRequestsPerMinute = maxRequestsPerMinute;
        }

        /// <summary>
        /// Validates the incoming request by checking API key, rate limits, and query parameters.
        /// Implements a pipeline pattern where each validation step must pass before proceeding.
        /// </summary>
        public async Task<APIGatewayProxyResponse> ValidateRequest(
            APIGatewayProxyRequest request,
            Func<APIGatewayProxyRequest, Task<APIGatewayProxyResponse>> next)
        {
            try
            {
                // Step 1: Validate API key for authentication
                if (!ValidateApiKey(request))
                {
                    _logger.LogWarning("Invalid API key in request");
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 401,
                        Body = "Invalid API key"
                    };
                }

                // Step 2: Check rate limits to prevent abuse
                if (!await ValidateRateLimit(request))
                {
                    _logger.LogWarning("Rate limit exceeded for request");
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 429,
                        Body = "Rate limit exceeded"
                    };
                }

                // Step 3: Validate query parameters for data integrity
                if (!ValidateQueryParameters(request))
                {
                    _logger.LogWarning("Invalid query parameters in request");
                    return new APIGatewayProxyResponse
                    {
                        StatusCode = 400,
                        Body = "Invalid query parameters"
                    };
                }

                // All validations passed, proceed with the request
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

        /// <summary>
        /// Validates the API key from request headers against the configured key.
        /// </summary>
        private bool ValidateApiKey(APIGatewayProxyRequest request)
        {
            if (!request.Headers.TryGetValue("X-API-Key", out var requestApiKey))
            {
                return false;
            }

            return requestApiKey == _apiKey;
        }

        /// <summary>
        /// Validates rate limits using a sliding window approach.
        /// TODO: Implement using DynamoDB for distributed rate limiting.
        /// </summary>
        private async Task<bool> ValidateRateLimit(APIGatewayProxyRequest request)
        {
            // TODO: Implement rate limiting using DynamoDB or Redis
            // For now, return true to allow all requests
            return true;
        }

        /// <summary>
        /// Validates query parameters for type safety and business rules.
        /// Ensures page size is within limits and date ranges are valid.
        /// </summary>
        private bool ValidateQueryParameters(APIGatewayProxyRequest request)
        {
            if (request.QueryStringParameters == null)
            {
                return true;
            }

            // Validate page size constraints (1-1000)
            if (request.QueryStringParameters.TryGetValue("pageSize", out var pageSizeStr))
            {
                if (!int.TryParse(pageSizeStr, out var pageSize) || pageSize < 1 || pageSize > 1000)
                {
                    return false;
                }
            }

            // Validate date range logic (start date must be before end date)
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