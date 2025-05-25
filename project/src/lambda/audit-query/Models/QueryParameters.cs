using System;
using AuditQuery.Exceptions;

namespace AuditQuery.Models
{
    public class QueryParameters
    {
        public string? UserId { get; set; }
        public string? SystemId { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public int PageSize { get; set; } = 50;
        public Dictionary<string, Amazon.DynamoDBv2.Model.AttributeValue>? LastEvaluatedKey { get; set; }

        public void Validate()
        {
            var errors = new List<string>();

            if (StartDate.HasValue && EndDate.HasValue && StartDate.Value > EndDate.Value)
            {
                errors.Add("Start date must be before end date");
            }

            if (PageSize < 1 || PageSize > 1000)
            {
                errors.Add("Page size must be between 1 and 1000");
            }

            if (string.IsNullOrWhiteSpace(UserId) && string.IsNullOrWhiteSpace(SystemId))
            {
                errors.Add("Either UserId or SystemId must be provided");
            }

            if (errors.Any())
            {
                throw new InvalidQueryParametersException(
                    $"Invalid query parameters: {string.Join(", ", errors)}");
            }
        }
    }
} 