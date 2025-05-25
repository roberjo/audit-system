using System;
using System.Threading.Tasks;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using AuditService.Models;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace AuditService.Services
{
    public class AuditService : IAuditService
    {
        private readonly IAmazonDynamoDB _dynamoDbClient;
        private readonly ILogger<AuditService> _logger;
        private const string TableName = "AuditEvents";

        public AuditService(IAmazonDynamoDB dynamoDbClient, ILogger<AuditService> logger)
        {
            _dynamoDbClient = dynamoDbClient ?? throw new ArgumentNullException(nameof(dynamoDbClient));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public async Task<bool> ProcessAuditEventAsync(AuditEvent auditEvent)
        {
            try
            {
                if (!await ValidateAuditEventAsync(auditEvent))
                {
                    _logger.LogWarning("Invalid audit event received: {AuditEvent}", JsonConvert.SerializeObject(auditEvent));
                    return false;
                }

                return await PersistAuditEventAsync(auditEvent);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing audit event: {AuditEvent}", JsonConvert.SerializeObject(auditEvent));
                return false;
            }
        }

        public async Task<bool> ValidateAuditEventAsync(AuditEvent auditEvent)
        {
            if (auditEvent == null)
            {
                _logger.LogError("Audit event is null");
                return false;
            }

            if (string.IsNullOrEmpty(auditEvent.UserId))
            {
                _logger.LogError("User ID is required");
                return false;
            }

            if (string.IsNullOrEmpty(auditEvent.Action))
            {
                _logger.LogError("Action is required");
                return false;
            }

            if (string.IsNullOrEmpty(auditEvent.ResourceType))
            {
                _logger.LogError("Resource type is required");
                return false;
            }

            if (string.IsNullOrEmpty(auditEvent.SourceApplication))
            {
                _logger.LogError("Source application is required");
                return false;
            }

            return true;
        }

        public async Task<bool> PersistAuditEventAsync(AuditEvent auditEvent)
        {
            try
            {
                var item = new Dictionary<string, AttributeValue>
                {
                    ["Id"] = new AttributeValue { S = auditEvent.Id },
                    ["Timestamp"] = new AttributeValue { S = auditEvent.Timestamp.ToString("o") },
                    ["UserId"] = new AttributeValue { S = auditEvent.UserId },
                    ["Action"] = new AttributeValue { S = auditEvent.Action },
                    ["ResourceType"] = new AttributeValue { S = auditEvent.ResourceType },
                    ["ResourceId"] = new AttributeValue { S = auditEvent.ResourceId },
                    ["SourceApplication"] = new AttributeValue { S = auditEvent.SourceApplication },
                    ["Details"] = new AttributeValue { S = JsonConvert.SerializeObject(auditEvent.Details) },
                    ["IpAddress"] = new AttributeValue { S = auditEvent.IpAddress },
                    ["UserAgent"] = new AttributeValue { S = auditEvent.UserAgent },
                    ["Status"] = new AttributeValue { S = auditEvent.Status },
                    ["ErrorMessage"] = new AttributeValue { S = auditEvent.ErrorMessage }
                };

                var request = new PutItemRequest
                {
                    TableName = TableName,
                    Item = item
                };

                await _dynamoDbClient.PutItemAsync(request);
                _logger.LogInformation("Successfully persisted audit event with ID: {AuditEventId}", auditEvent.Id);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error persisting audit event: {AuditEvent}", JsonConvert.SerializeObject(auditEvent));
                return false;
            }
        }
    }
} 