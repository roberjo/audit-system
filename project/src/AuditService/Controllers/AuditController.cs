using System.Threading.Tasks;
using AuditService.Models;
using AuditService.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace AuditService.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuditController : ControllerBase
    {
        private readonly IAuditService _auditService;
        private readonly ILogger<AuditController> _logger;

        public AuditController(IAuditService auditService, ILogger<AuditController> logger)
        {
            _auditService = auditService;
            _logger = logger;
        }

        [HttpPost]
        public async Task<IActionResult> SubmitAuditEvent([FromBody] AuditEvent auditEvent)
        {
            if (auditEvent == null)
            {
                return BadRequest("Audit event is required");
            }

            // Add request metadata
            auditEvent.IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString();
            auditEvent.UserAgent = HttpContext.Request.Headers["User-Agent"].ToString();

            var result = await _auditService.ProcessAuditEventAsync(auditEvent);

            if (result)
            {
                return Ok(new { message = "Audit event processed successfully", id = auditEvent.Id });
            }

            return StatusCode(500, "Failed to process audit event");
        }
    }
} 