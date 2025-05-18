# Business Logic and Frontend Architecture

## Overview

This document serves as a comprehensive guide for implementing the core business logic and frontend architecture of the Audit System. It is designed for developers who need to understand, maintain, or extend the system's functionality.

The document is divided into two main sections:

1. **Business Logic Implementation**
   - Details the core processing of audit events, including validation, enrichment, and persistence
   - Explains how sensitive data is handled and obfuscated
   - Describes the notification system for alerting users about important events
   - Provides TypeScript interfaces and class implementations for key business operations

2. **Frontend Architecture**
   - Outlines the React-based frontend structure with a focus on modularity and reusability
   - Implements secure authentication using Okta with role-based access control
   - Demonstrates state management using MobX for predictable data flow
   - Includes reusable components for common UI patterns
   - Provides error handling and API integration patterns

Each section includes practical code examples that follow industry best practices and demonstrate how to implement specific features. The examples are written in TypeScript and use modern React patterns to ensure type safety and maintainable code.

This document is essential for:
- New team members onboarding to the project
- Developers implementing new features
- Architects reviewing the system design
- QA engineers understanding the system behavior

## Business Logic Implementation

### 1. Audit Event Processing

#### Event Validation
```typescript
interface AuditEvent {
  eventId: string;
  eventType: EventType;
  userId: string;
  action: string;
  resourceId?: string;
  resourceType?: string;
  metadata: Record<string, any>;
  timestamp: string;
}

class AuditEventValidator {
  validateEvent(event: AuditEvent): ValidationResult {
    // Required fields check
    if (!event.eventId || !event.eventType || !event.userId || !event.action) {
      return { valid: false, errors: ['Missing required fields'] };
    }

    // Event type validation
    if (!Object.values(EventType).includes(event.eventType)) {
      return { valid: false, errors: ['Invalid event type'] };
    }

    // Timestamp validation
    if (!isValidISODate(event.timestamp)) {
      return { valid: false, errors: ['Invalid timestamp format'] };
    }

    // Resource validation if present
    if (event.resourceId && !event.resourceType) {
      return { valid: false, errors: ['Resource type required when resource ID is present'] };
    }

    return { valid: true };
  }
}
```

#### Event Enrichment
```typescript
class AuditEventEnricher {
  async enrichEvent(event: AuditEvent): Promise<AuditEvent> {
    // Add user context
    const userContext = await this.userService.getUserContext(event.userId);
    event.metadata.userContext = userContext;

    // Add resource context if applicable
    if (event.resourceId) {
      const resourceContext = await this.resourceService.getResourceContext(
        event.resourceId,
        event.resourceType
      );
      event.metadata.resourceContext = resourceContext;
    }

    // Add system context
    event.metadata.systemContext = {
      environment: process.env.ENVIRONMENT,
      region: process.env.AWS_REGION,
      version: process.env.APP_VERSION
    };

    return event;
  }
}
```

#### Event Persistence
```typescript
class AuditEventRepository {
  async saveEvent(event: AuditEvent): Promise<void> {
    // Save to DynamoDB for high-performance access
    await this.dynamoDB.put({
      TableName: 'audit_events',
      Item: this.mapToDynamoDBItem(event)
    });

    // Save to Aurora for detailed records
    await this.aurora.query(
      'INSERT INTO audit_event_details (event_id, event_type, user_id, ...) VALUES (?, ?, ?, ...)',
      [event.eventId, event.eventType, event.userId, ...]
    );
  }
}
```

### 2. Data Obfuscation

```typescript
class DataObfuscator {
  private readonly voltageClient: VoltageClient;

  async obfuscateSensitiveData(data: any, config: ObfuscationConfig): Promise<any> {
    const obfuscatedData = { ...data };

    for (const field of config.fields) {
      if (data[field]) {
        obfuscatedData[field] = await this.voltageClient.obfuscate(
          data[field],
          config.algorithm,
          config.keyId
        );
      }
    }

    return obfuscatedData;
  }
}
```

### 3. Notification System

```typescript
class NotificationService {
  async sendNotification(notification: Notification): Promise<void> {
    // Validate notification
    this.validateNotification(notification);

    // Determine recipients
    const recipients = await this.getRecipients(notification);

    // Send through appropriate channels
    for (const recipient of recipients) {
      if (recipient.preferences.email) {
        await this.emailService.send(recipient.email, notification);
      }
      if (recipient.preferences.slack) {
        await this.slackService.send(recipient.slackId, notification);
      }
    }

    // Log notification
    await this.notificationRepository.log(notification, recipients);
  }
}
```

## Frontend Architecture

### 1. Application Structure

```
frontend/
├── src/
│   ├── components/
│   │   ├── common/
│   │   │   ├── Button/
│   │   │   ├── Input/
│   │   │   ├── Modal/
│   │   │   └── Table/
│   │   ├── layout/
│   │   │   ├── Header/
│   │   │   ├── Sidebar/
│   │   │   └── Footer/
│   │   └── features/
│   │       ├── audit/
│   │       ├── users/
│   │       └── reports/
│   ├── hooks/
│   │   ├── useAuth.ts
│   │   ├── useNotifications.ts
│   │   └── useAuditEvents.ts
│   ├── services/
│   │   ├── api.ts
│   │   ├── auth.ts
│   │   └── notifications.ts
│   ├── store/
│   │   ├── auth/
│   │   ├── audit/
│   │   └── ui/
│   ├── utils/
│   │   ├── validation.ts
│   │   ├── formatting.ts
│   │   └── permissions.ts
│   └── types/
│       ├── auth.ts
│       ├── audit.ts
│       └── user.ts
```

### 2. Authentication Implementation

```typescript
// hooks/useAuth.ts
interface AuthState {
  isAuthenticated: boolean;
  user: User | null;
  permissions: string[];
  loading: boolean;
}

const useAuth = () => {
  const [state, setState] = useState<AuthState>({
    isAuthenticated: false,
    user: null,
    permissions: [],
    loading: true
  });

  const login = async (credentials: Credentials) => {
    try {
      const response = await oktaAuth.signIn(credentials);
      const user = await oktaAuth.getUser();
      const permissions = await oktaAuth.getPermissions();
      
      setState({
        isAuthenticated: true,
        user,
        permissions,
        loading: false
      });
    } catch (error) {
      handleAuthError(error);
    }
  };

  return { ...state, login, logout };
};

// components/common/ProtectedRoute.tsx
const ProtectedRoute: React.FC<ProtectedRouteProps> = ({
  requiredPermissions,
  children
}) => {
  const { isAuthenticated, permissions, loading } = useAuth();

  if (loading) {
    return <LoadingSpinner />;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" />;
  }

  if (requiredPermissions && !hasRequiredPermissions(permissions, requiredPermissions)) {
    return <Navigate to="/unauthorized" />;
  }

  return <>{children}</>;
};
```

### 3. State Management

```typescript
// store/audit/auditStore.ts
class AuditStore {
  @observable events: AuditEvent[] = [];
  @observable loading: boolean = false;
  @observable error: Error | null = null;

  @action
  async fetchEvents(filters: EventFilters) {
    this.loading = true;
    try {
      const events = await auditService.getEvents(filters);
      this.events = events;
    } catch (error) {
      this.error = error;
    } finally {
      this.loading = false;
    }
  }
}

// hooks/useAuditEvents.ts
const useAuditEvents = () => {
  const store = useStore(AuditStore);

  useEffect(() => {
    store.fetchEvents({});
  }, []);

  return {
    events: store.events,
    loading: store.loading,
    error: store.error,
    fetchEvents: store.fetchEvents
  };
};
```

### 4. Component Implementation

```typescript
// components/features/audit/AuditEventList.tsx
const AuditEventList: React.FC = () => {
  const { events, loading, error } = useAuditEvents();
  const { formatDate } = useFormatting();
  const { hasPermission } = usePermissions();

  if (loading) return <LoadingSpinner />;
  if (error) return <ErrorMessage error={error} />;

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHeaderCell>Event Type</TableHeaderCell>
          <TableHeaderCell>User</TableHeaderCell>
          <TableHeaderCell>Action</TableHeaderCell>
          <TableHeaderCell>Timestamp</TableHeaderCell>
          {hasPermission('VIEW_DETAILS') && (
            <TableHeaderCell>Details</TableHeaderCell>
          )}
        </TableRow>
      </TableHeader>
      <TableBody>
        {events.map(event => (
          <TableRow key={event.eventId}>
            <TableCell>{event.eventType}</TableCell>
            <TableCell>{event.userId}</TableCell>
            <TableCell>{event.action}</TableCell>
            <TableCell>{formatDate(event.timestamp)}</TableCell>
            {hasPermission('VIEW_DETAILS') && (
              <TableCell>
                <EventDetailsButton event={event} />
              </TableCell>
            )}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
};
```

### 5. Notification System

```typescript
// hooks/useNotifications.ts
const useNotifications = () => {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const { user } = useAuth();

  useEffect(() => {
    const subscription = notificationService.subscribe(user.id, (notification) => {
      setNotifications(prev => [...prev, notification]);
    });

    return () => subscription.unsubscribe();
  }, [user.id]);

  return {
    notifications,
    markAsRead: (id: string) => {
      setNotifications(prev =>
        prev.map(n => n.id === id ? { ...n, read: true } : n)
      );
    }
  };
};

// components/common/NotificationCenter.tsx
const NotificationCenter: React.FC = () => {
  const { notifications, markAsRead } = useNotifications();

  return (
    <Popover>
      <PopoverTrigger>
        <NotificationIcon count={notifications.filter(n => !n.read).length} />
      </PopoverTrigger>
      <PopoverContent>
        <NotificationList>
          {notifications.map(notification => (
            <NotificationItem
              key={notification.id}
              notification={notification}
              onRead={() => markAsRead(notification.id)}
            />
          ))}
        </NotificationList>
      </PopoverContent>
    </Popover>
  );
};
```

### 6. User Profile Management

```typescript
// components/features/users/UserProfile.tsx
const UserProfile: React.FC = () => {
  const { user, updateUser } = useAuth();
  const [formData, setFormData] = useState(user);
  const { showNotification } = useNotifications();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await updateUser(formData);
      showNotification({
        type: 'success',
        message: 'Profile updated successfully'
      });
    } catch (error) {
      showNotification({
        type: 'error',
        message: 'Failed to update profile'
      });
    }
  };

  return (
    <Form onSubmit={handleSubmit}>
      <FormField
        label="Email"
        value={formData.email}
        onChange={e => setFormData({ ...formData, email: e.target.value })}
      />
      <FormField
        label="Name"
        value={formData.name}
        onChange={e => setFormData({ ...formData, name: e.target.value })}
      />
      <Button type="submit">Update Profile</Button>
    </Form>
  );
};
```

### 7. Error Handling

```typescript
// utils/errorBoundary.tsx
class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    errorReportingService.logError(error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return <ErrorFallback error={this.state.error} />;
    }

    return this.props.children;
  }
}

// components/common/ErrorFallback.tsx
const ErrorFallback: React.FC<{ error: Error }> = ({ error }) => {
  const { resetError } = useErrorBoundary();

  return (
    <div className="error-fallback">
      <h2>Something went wrong</h2>
      <p>{error.message}</p>
      <Button onClick={resetError}>Try again</Button>
    </div>
  );
};
```

### 8. API Integration

```typescript
// services/api.ts
const api = axios.create({
  baseURL: process.env.API_URL,
  timeout: 10000
});

api.interceptors.request.use(async (config) => {
  const token = await oktaAuth.getAccessToken();
  config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  response => response,
  async error => {
    if (error.response?.status === 401) {
      await oktaAuth.renewToken();
      return api(error.config);
    }
    return Promise.reject(error);
  }
);

// services/audit.ts
export const auditService = {
  getEvents: async (filters: EventFilters) => {
    const response = await api.get('/audit-events', { params: filters });
    return response.data;
  },

  createEvent: async (event: AuditEvent) => {
    const response = await api.post('/audit-events', event);
    return response.data;
  }
};
```

This documentation provides a comprehensive guide for implementing the business logic and frontend architecture of the Audit System. The code examples demonstrate best practices for:

1. Modular component design
2. Secure authentication with Okta
3. Role-based access control
4. State management with MobX
5. Error handling and reporting
6. API integration
7. Notification system
8. User profile management

Would you like me to provide more details about any specific aspect of the implementation? 