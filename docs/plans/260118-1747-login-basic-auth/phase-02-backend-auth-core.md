# Phase 02: Backend Auth Core

## Context Links
- [Parent Plan](plan.md)
- [Phase 01: Database Schema](phase-01-database-schema.md)
- [Flask Auth Research](research/researcher-01-flask-auth-report.md)

## Overview
| Field | Value |
|-------|-------|
| Priority | P1 - Critical |
| Status | in_progress |
| Review Status | reviewed (8.5/10) |
| Estimated Effort | 3h |

Implement authentication core using hexagonal architecture: domain services, ports (interfaces), and adapters (implementations).

## Key Insights
- Domain layer has NO infrastructure dependencies
- Ports define interfaces (protocols) for external integrations
- Adapters implement ports with concrete libraries
- Flask-JWT-Extended for JWT, Flask-Login for sessions
- Argon2 via argon2-cffi for password hashing

## Requirements

### Functional
- AuthService for login/logout business logic
- AuthorizationService for RBAC checks
- PasswordHasher port/adapter (Argon2)
- TokenIssuer port/adapter (JWT)
- SessionManager port/adapter (Flask-Login)

### Non-Functional
- Domain layer pure (no Flask imports)
- All dependencies injected via ports
- Testable without infrastructure

## Architecture

### Hexagonal Structure
```
app/
├── domain/
│   ├── entities/          # User, Role, Permission (from Phase 1)
│   ├── services/
│   │   ├── auth_service.py         # Login/logout logic
│   │   └── authorization_service.py # RBAC checks
│   ├── exceptions/
│   │   └── auth_exceptions.py
│   └── value_objects/
│       └── credentials.py          # Email/Password validation
├── application/
│   ├── ports/
│   │   ├── password_hasher_port.py
│   │   ├── token_issuer_port.py
│   │   ├── session_manager_port.py
│   │   └── user_repository_port.py
│   └── usecases/
│       ├── login_usecase.py
│       └── logout_usecase.py
└── infrastructure/
    └── adapters/
        ├── argon2_password_hasher.py
        ├── jwt_token_issuer.py
        └── flask_session_manager.py
```

## Related Code Files

### Files to Create
- `app/domain/services/auth_service.py`
- `app/domain/services/authorization_service.py`
- `app/domain/exceptions/auth_exceptions.py`
- `app/domain/value_objects/credentials.py`
- `app/application/ports/password_hasher_port.py`
- `app/application/ports/token_issuer_port.py`
- `app/application/ports/session_manager_port.py`
- `app/application/usecases/login_usecase.py`
- `app/application/usecases/logout_usecase.py`
- `app/infrastructure/adapters/argon2_password_hasher.py`
- `app/infrastructure/adapters/jwt_token_issuer.py`
- `app/infrastructure/adapters/flask_session_manager.py`

### Files to Modify
- `wiring.py` (add new ports to container)
- `pyproject.toml` (add Flask-JWT-Extended, Flask-Login)

## Implementation Steps

### Step 1: Add Dependencies
```bash
uv add flask-jwt-extended flask-login pydantic
```

### Step 2: Create Domain Exceptions

**`app/domain/exceptions/auth_exceptions.py`**
```python
class AuthenticationError(Exception):
    """Base authentication exception."""
    pass

class InvalidCredentialsError(AuthenticationError):
    """Invalid email or password."""
    pass

class UserNotFoundError(AuthenticationError):
    """User does not exist."""
    pass

class UserInactiveError(AuthenticationError):
    """User account is deactivated."""
    pass

class AuthorizationError(Exception):
    """Base authorization exception."""
    pass

class InsufficientPermissionsError(AuthorizationError):
    """User lacks required permissions."""
    pass

class RoleNotFoundError(AuthorizationError):
    """Role does not exist."""
    pass
```

### Step 3: Create Value Objects

**`app/domain/value_objects/credentials.py`**
```python
from dataclasses import dataclass
import re

@dataclass(frozen=True)
class Email:
    value: str

    def __post_init__(self):
        if not self._is_valid():
            raise ValueError(f"Invalid email: {self.value}")

    def _is_valid(self) -> bool:
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return bool(re.match(pattern, self.value))

    def __str__(self) -> str:
        return self.value.lower()

@dataclass(frozen=True)
class Password:
    value: str

    def __post_init__(self):
        if len(self.value) < 8:
            raise ValueError("Password must be at least 8 characters")
```

### Step 4: Create Ports (Interfaces)

**`app/application/ports/password_hasher_port.py`**
```python
from typing import Protocol

class PasswordHasherPort(Protocol):
    """Port for password hashing operations."""

    def hash(self, password: str) -> str:
        """Hash a plaintext password."""
        ...

    def verify(self, password: str, hash: str) -> bool:
        """Verify password against hash."""
        ...
```

**`app/application/ports/token_issuer_port.py`**
```python
from typing import Protocol, Dict, Any, Optional
from uuid import UUID

class TokenIssuerPort(Protocol):
    """Port for JWT token operations."""

    def create_access_token(self, user_id: UUID, additional_claims: Dict[str, Any] = None) -> str:
        """Create short-lived access token."""
        ...

    def create_refresh_token(self, user_id: UUID) -> str:
        """Create long-lived refresh token."""
        ...

    def verify_token(self, token: str) -> Optional[Dict[str, Any]]:
        """Verify and decode token. Returns claims or None."""
        ...

    def revoke_token(self, jti: str) -> None:
        """Add token to blacklist."""
        ...
```

**`app/application/ports/session_manager_port.py`**
```python
from typing import Protocol, Optional
from uuid import UUID

class SessionManagerPort(Protocol):
    """Port for session management."""

    def create_session(self, user_id: UUID) -> str:
        """Create new session, return session ID."""
        ...

    def get_user_id(self, session_id: str) -> Optional[UUID]:
        """Get user ID from session."""
        ...

    def destroy_session(self, session_id: str) -> None:
        """Destroy session."""
        ...
```

### Step 5: Create Domain Services

**`app/domain/services/auth_service.py`**
```python
from typing import Tuple, Optional
from uuid import UUID
from app.domain.exceptions.auth_exceptions import (
    InvalidCredentialsError, UserNotFoundError, UserInactiveError
)
from app.application.ports.password_hasher_port import PasswordHasherPort
from app.application.ports.user_repository_port import UserRepositoryPort

class AuthService:
    """Domain service for authentication logic."""

    def __init__(
        self,
        user_repository: UserRepositoryPort,
        password_hasher: PasswordHasherPort
    ):
        self._user_repo = user_repository
        self._hasher = password_hasher

    def authenticate(self, email: str, password: str) -> UUID:
        """
        Authenticate user with email/password.
        Returns user ID if successful.
        Raises: InvalidCredentialsError, UserNotFoundError, UserInactiveError
        """
        user = self._user_repo.find_by_email(email.lower())
        if not user:
            raise UserNotFoundError(f"User not found: {email}")

        if not user.is_active:
            raise UserInactiveError("User account is deactivated")

        if not self._hasher.verify(password, user.password_hash):
            raise InvalidCredentialsError("Invalid credentials")

        return user.id

    def hash_password(self, password: str) -> str:
        """Hash password for storage."""
        return self._hasher.hash(password)
```

**`app/domain/services/authorization_service.py`**
```python
from typing import List, Set
from uuid import UUID
from app.application.ports.user_repository_port import UserRepositoryPort

class AuthorizationService:
    """Domain service for authorization/RBAC logic."""

    def __init__(self, user_repository: UserRepositoryPort):
        self._user_repo = user_repository

    def get_user_permissions(self, user_id: UUID) -> Set[str]:
        """Get all permissions for user (aggregated from roles)."""
        user = self._user_repo.find_by_id(user_id)
        if not user:
            return set()

        permissions = set()
        for role in user.roles:
            for perm in role.permissions:
                permissions.add(perm.name)
        return permissions

    def has_permission(self, user_id: UUID, permission: str) -> bool:
        """Check if user has specific permission."""
        return permission in self.get_user_permissions(user_id)

    def has_any_permission(self, user_id: UUID, permissions: List[str]) -> bool:
        """Check if user has any of the permissions."""
        user_perms = self.get_user_permissions(user_id)
        return bool(user_perms.intersection(permissions))

    def has_all_permissions(self, user_id: UUID, permissions: List[str]) -> bool:
        """Check if user has all permissions."""
        user_perms = self.get_user_permissions(user_id)
        return all(p in user_perms for p in permissions)

    def has_role(self, user_id: UUID, role_name: str) -> bool:
        """Check if user has specific role."""
        user = self._user_repo.find_by_id(user_id)
        if not user:
            return False
        return any(r.name == role_name for r in user.roles)
```

### Step 6: Create Adapters

**`app/infrastructure/adapters/argon2_password_hasher.py`**
```python
from argon2 import PasswordHasher as Argon2Hasher
from argon2.exceptions import VerifyMismatchError

class Argon2PasswordHasher:
    """Argon2 implementation of PasswordHasherPort."""

    def __init__(self):
        self._hasher = Argon2Hasher(
            time_cost=2,
            memory_cost=65536,  # 64 MB
            parallelism=1
        )

    def hash(self, password: str) -> str:
        return self._hasher.hash(password)

    def verify(self, password: str, hash: str) -> bool:
        try:
            self._hasher.verify(hash, password)
            return True
        except VerifyMismatchError:
            return False
```

**`app/infrastructure/adapters/jwt_token_issuer.py`**
```python
from datetime import timedelta
from typing import Dict, Any, Optional
from uuid import UUID
from flask_jwt_extended import create_access_token, create_refresh_token, decode_token
from flask_jwt_extended.exceptions import JWTDecodeError

class JWTTokenIssuer:
    """Flask-JWT-Extended implementation of TokenIssuerPort."""

    def __init__(self, access_expires: int = 30, refresh_expires: int = 7):
        self._access_expires = timedelta(minutes=access_expires)
        self._refresh_expires = timedelta(days=refresh_expires)

    def create_access_token(self, user_id: UUID, additional_claims: Dict[str, Any] = None) -> str:
        claims = additional_claims or {}
        return create_access_token(
            identity=str(user_id),
            additional_claims=claims,
            expires_delta=self._access_expires
        )

    def create_refresh_token(self, user_id: UUID) -> str:
        return create_refresh_token(
            identity=str(user_id),
            expires_delta=self._refresh_expires
        )

    def verify_token(self, token: str) -> Optional[Dict[str, Any]]:
        try:
            return decode_token(token)
        except JWTDecodeError:
            return None

    def revoke_token(self, jti: str) -> None:
        # Store in Redis blacklist (implementation in Phase 3)
        pass
```

### Step 7: Create Login Use Case

**`app/application/usecases/login_usecase.py`**
```python
from dataclasses import dataclass
from typing import Optional
from uuid import UUID
from app.domain.services.auth_service import AuthService
from app.domain.services.authorization_service import AuthorizationService
from app.application.ports.token_issuer_port import TokenIssuerPort

@dataclass
class LoginResult:
    user_id: UUID
    access_token: str
    refresh_token: str
    permissions: list

class LoginUseCase:
    """Application use case for user login."""

    def __init__(
        self,
        auth_service: AuthService,
        authorization_service: AuthorizationService,
        token_issuer: TokenIssuerPort
    ):
        self._auth = auth_service
        self._authz = authorization_service
        self._tokens = token_issuer

    def execute(self, email: str, password: str) -> LoginResult:
        """
        Execute login flow.
        1. Authenticate credentials
        2. Get user permissions
        3. Generate tokens
        """
        user_id = self._auth.authenticate(email, password)
        permissions = list(self._authz.get_user_permissions(user_id))

        access_token = self._tokens.create_access_token(
            user_id,
            {"permissions": permissions}
        )
        refresh_token = self._tokens.create_refresh_token(user_id)

        return LoginResult(
            user_id=user_id,
            access_token=access_token,
            refresh_token=refresh_token,
            permissions=permissions
        )
```

### Step 8: Update Wiring/Container

**Update `wiring.py`**
```python
# Add new ports
class PasswordHasherPort(Protocol):
    def hash(self, password: str) -> str: ...
    def verify(self, password: str, hash: str) -> bool: ...

class TokenIssuerPort(Protocol):
    def create_access_token(self, user_id: UUID, claims: dict = None) -> str: ...
    def create_refresh_token(self, user_id: UUID) -> str: ...
    def verify_token(self, token: str) -> Optional[dict]: ...

@dataclass
class Container:
    # ... existing
    password_hasher: Optional[PasswordHasherPort] = None
    token_issuer: Optional[TokenIssuerPort] = None
    auth_service: Optional[AuthService] = None
    authorization_service: Optional[AuthorizationService] = None
```

## Todo List

- [x] Create domain exceptions module
- [x] Create value objects (Email, Password)
- [x] Create PasswordHasherPort interface
- [x] Create TokenIssuerPort interface
- [x] Create SessionManagerPort interface
- [x] Implement AuthService domain service
- [x] Implement AuthorizationService domain service
- [x] Create Argon2PasswordHasher adapter
- [x] Create JWTTokenIssuer adapter
- [x] Create LoginUseCase
- [x] Update wiring.py with new ports
- [ ] Write unit tests for domain services (deferred to Phase 06)
- [ ] Create flask_session_manager.py adapter (optional - deferred to Phase 03)

## Success Criteria

- [ ] AuthService authenticates valid credentials
- [ ] AuthService rejects invalid credentials
- [ ] AuthorizationService checks permissions correctly
- [ ] Password hashing/verification works
- [ ] JWT tokens can be created and verified
- [ ] All domain logic testable without infrastructure

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Port interface mismatch | Medium | Medium | Define protocols clearly |
| Circular imports | Medium | Low | Strict layer separation |
| JWT library version issues | Low | Medium | Pin versions |

## Security Considerations

- Never log passwords or hashes
- Domain services throw generic errors externally
- Token claims minimal (user_id + permissions)
- Argon2 parameters tuned for security

## Next Steps

After this phase:
-> [Phase 03: Backend Auth Endpoints](phase-03-backend-auth-endpoints.md)

---

## Code Review Notes (2026-01-18)

**Score: 8.5/10** | [Full Report](reports/code-reviewer-260118-1909-phase02-backend-auth-core.md)

### Key Findings
- Excellent hexagonal architecture compliance
- Missing `flask_session_manager.py` (defer to Phase 03)
- `UserRepositoryPort` uses `Any` type - consider typed protocol
- Token revocation is TODO (planned for Phase 03 Redis)

### Action Items for Phase 03
1. Implement Redis token blacklist in `revoke_token()`
2. Create `flask_session_manager.py` adapter
3. Consolidate auth errors in API layer to prevent user enumeration
