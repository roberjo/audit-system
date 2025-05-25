using Amazon.DynamoDBv2.DocumentModel;
using System.Threading.Tasks;

namespace AuditQuery.Services;

public interface IAuditQueryService
{
    Task<QueryResult> QueryAuditRecordsAsync(QueryParameters parameters);
} 