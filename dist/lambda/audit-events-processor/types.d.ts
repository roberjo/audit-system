export interface AuditEvent {
    id: string;
    userId: string;
    systemId: string;
    dataBefore: Record<string, any>;
    dataAfter: Record<string, any>;
    timestamp: string;
    ttl: number;
}
