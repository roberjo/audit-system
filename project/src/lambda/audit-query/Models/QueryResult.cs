using Amazon.DynamoDBv2.DocumentModel;
using System.Collections.Generic;

namespace AuditQuery.Models;

public class QueryResult
{
    public List<Document> Items { get; set; } = new();
    public Dictionary<string, AttributeValue>? LastEvaluatedKey { get; set; }
} 