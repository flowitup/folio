# Flask Authentication with Hexagonal Architecture - Research Report

## Recommended Tech Stack

| Component | Library | Version | Rationale |
|-----------|---------|---------|-----------|
| JWT Handling | Flask-JWT-Extended | 4.7+ | Feature-rich (refresh tokens, token freshness, blacklisting), Flask-optimized |
| Password Hashing | Argon2 (argon2-cffi) | 23.1+ | Winner of Password Hashing Competition, GPU/ASIC resistant, configurable |
| Session Management | Flask-Login | 0.6+ | Session persistence, user_loader integration |
| CSRF Protection | Flask-WTF | 1.2+ | Automatic token generation, HttpOnly cookies |
| Data Validation | Pydantic | 2.0+ | Schema validation, response models |

## Hexagonal Architecture Pattern for Auth

### Domain Layer (Core)
```
domain/
├── entities/
│   └── user.py              # User aggregate root, password hashing logic
├── value_objects/
│   ├── email.py             # Email validation
│   └── password.py          # Password rules enforcement
├── repositories/            # Interfaces ONLY
│   └── user_repository.py
├── services/
│   └── auth_service.py      # Domain business logic (validate, hash, check)
└── exceptions/
    └── auth_exceptions.py   # Domain-specific errors
```

### Ports & Adapters Layer
```
application/
├── ports/
│   ├── user_repository_port.py      # Abstract interface
│   ├── password_hasher_port.py      # Abstract hasher
│   ├── token_issuer_port.py         # Abstract token generation
│   └── session_manager_port.py      # Abstract session handling
└── usecases/
    ├── login_usecase.py
    ├── register_usecase.py
    └── refresh_token_usecase.py

infrastructure/
├── adapters/
│   ├── sqlalchemy_user_repository.py   # Implements UserRepository
│   ├── argon2_password_hasher.py       # Implements PasswordHasher
│   ├── flask_jwt_token_issuer.py       # Implements TokenIssuer (Flask-JWT-Extended)
│   └── flask_session_manager.py        # Implements SessionManager (Flask-Login)
└── api/
    ├── auth_routes.py                  # Flask blueprints
    ├── middleware/
    │   └── auth_middleware.py          # JWT verification decorators
    └── schema/
        └── auth_schemas.py             # Pydantic request/response models
```

## Dual Auth Approach (JWT + Session)

### Strategy
- **JWT**: For API clients (mobile, SPA) - stateless, scalable
- **Session Cookies**: For web browsers - CSRF protection, HttpOnly flag

### Implementation
```python
# Auth middleware supports both
@auth.verify_token
def verify_jwt(token):
    # Domain service validates JWT
    return auth_service.validate_jwt(token)

@auth.verify_session
def verify_session(session_data):
    # Domain service validates session
    return auth_service.validate_session(session_data)

# Routes accept both
@app.route('/api/protected')
@jwt_required(optional=True)
@login_required(optional=True)
def protected():
    user = get_jwt_identity() or current_user
    return {"user_id": user.id}
```

### Token Lifecycle
- **Access Token**: 15-30 min expiry, use for requests
- **Refresh Token**: 7-30 days expiry, rotate on each refresh
- **Reuse Detection**: Track refresh tokens in DB, invalidate on reuse (compromised token detection)

## RBAC Schema Design

### Database Models
```python
# Users
class User:
    id: UUID
    email: str (unique)
    password_hash: str (argon2)
    is_active: bool
    created_at: datetime
    updated_at: datetime

# Roles
class Role:
    id: UUID
    name: str (unique) # 'admin', 'user', 'moderator'
    description: str

# Permissions
class Permission:
    id: UUID
    name: str (unique) # 'user:create', 'user:delete', 'post:edit'
    resource: str
    action: str

# User-Role mapping
class UserRole:
    user_id: UUID (FK)
    role_id: UUID (FK)
    assigned_at: datetime

# Role-Permission mapping
class RolePermission:
    role_id: UUID (FK)
    permission_id: UUID (FK)
```

### Authorization Logic (Domain Service)
```python
class AuthorizationService:
    def has_permission(self, user_id: UUID, required_permission: str) -> bool:
        user_roles = self.role_repository.get_user_roles(user_id)
        for role in user_roles:
            permissions = self.perm_repository.get_role_permissions(role.id)
            if any(p.name == required_permission for p in permissions):
                return True
        return False

    def has_role(self, user_id: UUID, role_name: str) -> bool:
        return self.role_repository.user_has_role(user_id, role_name)
```

### Decorator Pattern (Infrastructure)
```python
from functools import wraps

def require_role(*roles):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            user = current_user  # or get_jwt_identity()
            if not auth_service.has_role(user.id, roles):
                return {"error": "Forbidden"}, 403
            return f(*args, **kwargs)
        return wrapper
    return decorator

def require_permission(*permissions):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            user = current_user
            for perm in permissions:
                if not auth_service.has_permission(user.id, perm):
                    return {"error": "Forbidden"}, 403
            return f(*args, **kwargs)
        return wrapper
    return decorator
```

## Security Best Practices

1. **Password Storage**: Argon2 with configurable time/memory cost (time_cost=2, memory_cost=65536 MB)
2. **Token Security**:
   - Short-lived access tokens (15-30 min)
   - Secure httpOnly, sameSite=Strict for cookies
   - Rotate refresh tokens on each use
   - Store refresh tokens in DB with expiry/used flags

3. **CSRF Protection**: Flask-WTF automatic token validation for forms + SameSite=Lax for session cookies

4. **Rate Limiting**: Implement per-IP rate limiting on login/register endpoints

5. **Input Validation**: Pydantic models validate all input before domain service

6. **Error Handling**: Domain exceptions map to 401/403 HTTP responses, no sensitive info in messages

7. **Session Management**: Use Flask-Login with user_loader for session persistence, mark session as fresh only after password verification

## Key Decisions

| Decision | Chosen | Alternative | Why |
|----------|--------|-------------|-----|
| JWT Library | Flask-JWT-Extended | PyJWT | Built-in refresh, freshness, blacklisting support |
| Hashing | Argon2 | bcrypt | GPU-resistant, configurable, modern standard |
| Auth Type | Dual (JWT + Session) | JWT only | Serves different client types, maximum compatibility |
| RBAC Granularity | Permission-based | Role-only | Scales better, flexible authorization rules |
| Token Rotation | Every refresh | Sliding window | Minimizes compromised token window |

## Unresolved Questions

1. Should refresh token rotation use sliding window or strict rotation? (Strict chosen for security)
2. Will session-JWT dual approach create confusion in API versioning?
3. Redis vs DB for token blacklisting - performance tradeoff?

## Sources

- [Flask Security Best Practices 2025](https://hub.corgea.com/articles/flask-security-best-practices-2025)
- [Flask-JWT-Extended Documentation](https://flask-jwt-extended.readthedocs.io/)
- [Hexagonal Architecture - AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/hexagonal-architecture.html)
- [Python Hexagonal Architecture Patterns](https://dev.to/hieutran25/building-maintainable-python-applications-with-hexagonal-architecture-and-domain-driven-design-chp)
- [Argon2 vs bcrypt Comparison](https://guptadeepak.com/comparative-analysis-of-password-hashing-algorithms-argon2-bcrypt-scrypt-and-pbkdf2/)
- [Refresh Token Rotation Guide](https://www.descope.com/blog/post/refresh-token-rotation)
- [RBAC in Flask](https://www.permit.io/blog/implement-role-based-access-control-in-flask)
- [Token Freshness Pattern](https://flask-jwt-extended.readthedocs.io/en/stable/refreshing_tokens.html)
