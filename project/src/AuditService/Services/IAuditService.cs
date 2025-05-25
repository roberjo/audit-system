using System.Threading.Tasks;
using AuditService.Models;

namespace AuditService.Services
{
    public interface IAuditService
    {
        Task<bool> ProcessAuditEventAsync(AuditEvent auditEvent);
        Task<bool> ValidateAuditEventAsync(AuditEvent auditEvent);
        Task<bool> PersistAuditEventAsync(AuditEvent auditEvent);
    }
} 