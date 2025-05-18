using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace AuditEventsProcessor
{
    public class AuditEvent
    {
        [JsonProperty("eventId")]
        public string EventId { get; set; }

        [JsonProperty("timestamp")]
        public DateTime Timestamp { get; set; }

        [JsonProperty("userId")]
        public string UserId { get; set; }

        [JsonProperty("action")]
        public string Action { get; set; }

        [JsonProperty("resourceType")]
        public string ResourceType { get; set; }

        [JsonProperty("resourceId")]
        public string ResourceId { get; set; }

        [JsonProperty("sourceApplication")]
        public string SourceApplication { get; set; }

        [JsonProperty("details")]
        public Dictionary<string, string> Details { get; set; }

        [JsonProperty("ipAddress")]
        public string IpAddress { get; set; }

        [JsonProperty("userAgent")]
        public string UserAgent { get; set; }

        [JsonProperty("status")]
        public string Status { get; set; }

        [JsonProperty("errorMessage")]
        public string ErrorMessage { get; set; }
    }
} 