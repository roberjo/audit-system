using System;

namespace AuditQuery.Exceptions
{
    public class AuditQueryException : Exception
    {
        public AuditQueryException(string message) : base(message) { }
        public AuditQueryException(string message, Exception innerException) : base(message, innerException) { }
    }

    public class InvalidQueryParametersException : AuditQueryException
    {
        public InvalidQueryParametersException(string message) : base(message) { }
    }

    public class DynamoDbQueryException : AuditQueryException
    {
        public DynamoDbQueryException(string message, Exception innerException) 
            : base(message, innerException) { }
    }

    public class UnauthorizedQueryException : AuditQueryException
    {
        public UnauthorizedQueryException(string message) : base(message) { }
    }
} 