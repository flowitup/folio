# Backend Code Standards

**Last Updated:** 2026-01-18
**Version:** 1.0

## Overview

Backend code standards for Flask 3.0 project using SQLAlchemy, PostgreSQL, Redis, pytest, and following hexagonal architecture principles.

## Architecture Layers

### Domain Layer

**Location:** `app/domain/`

**Responsibilities:**
- Business entities and rules
- Pure business logic (no framework dependencies)
- Domain events

**Structure:**
```
domain/
├── entities/
│   ├── user.py         # User aggregate root
│   ├── role.py         # Role entity
│   └── permission.py   # Permission entity
├── value_objects/
│   ├── email.py        # Email validation
│   └── hashed_password.py
└── exceptions/
    ├── auth_exceptions.py
    └── validation_exceptions.py
```

**Principles:**
- Framework-agnostic
- Rich domain models
- Encapsulated business logic

### Application Layer

**Location:** `app/application/`

**Responsibilities:**
- Orchestrate domain logic
- Implement business workflows
- Coordinate between domain and infrastructure
- Transaction management

**Structure:**
```
application/
└── auth/
    ├── login_usecase.py
    └── ports.py         # Interfaces (IUserRepository, etc.)
```

**Key Components:**
- `LoginUseCase` - Authenticate user, issue tokens
- `ports.py` - Interface definitions (IUserRepository, ITokenIssuer, etc.)

**Dependencies:** Domain entities, ports (interfaces)

### Infrastructure Layer

**Location:** `app/infrastructure/`

**Responsibilities:**
- External service integration
- Database access
- Authentication mechanisms
- Authorization services

**Structure:**
```
infrastructure/
├── database/
│   ├── models/         # SQLAlchemy models
│   └── repositories/   # Repository implementations
├── auth/
│   ├── jwt_token_issuer.py
│   └── password_hasher.py
├── authorization/
│   └── rbac_service.py
└── rate_limiter.py
```

**Technology:**
- SQLAlchemy 2.0
- Alembic (migrations)
- Redis (token blacklist, rate limiting)
- Argon2 (password hashing)

### API Layer

**Location:** `app/api/v1/`

**Responsibilities:**
- HTTP request/response handling
- Input validation (Pydantic schemas)
- Authentication/authorization (JWT middleware)
- Rate limiting
- Error serialization

**Key Components:**
- `routes.py` - Endpoint definitions
- `schemas.py` - Request/response models
- `middleware.py` - JWT verification

**Technology:**
- Flask 3.0
- Flask-JWT-Extended
- Pydantic
- Flask-Limiter

## Domain Layer Standards

### Entities

**Rules:**
- Mutable state
- Unique identity (UUID)
- Business logic methods
- No framework dependencies

**Example:**
```python
from dataclasses import dataclass
from uuid import UUID

@dataclass
class User:
    id: UUID
    email: Email  # Value object
    password_hash: HashedPassword  # Value object
    is_active: bool = True

    def activate(self) -> None:
        self.is_active = True

    def deactivate(self) -> None:
        self.is_active = False
```

### Value Objects

**Rules:**
- Immutable (frozen dataclass)
- Validation in `__post_init__`
- Equality by value
- No identity

**Example:**
```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Email:
    value: str

    def __post_init__(self):
        if "@" not in self.value:
            raise ValueError("Invalid email format")
```

### Domain Exceptions

**Rules:**
- Inherit from custom base exception
- Descriptive names
- Include context in message

**Example:**
```python
class AuthenticationError(Exception):
    """Base auth exception."""
    pass

class InvalidCredentialsError(AuthenticationError):
    """Invalid email or password."""
    pass

class UserNotFoundError(AuthenticationError):
    """User not found."""
    pass
```

## Application Layer Standards

### Use Cases

**Rules:**
- Single responsibility (one workflow)
- Name format: `{Verb}{Noun}UseCase`
- `execute()` method as entry point
- Return domain entities or DTOs

**Example:**
```python
from dataclasses import dataclass
from app.domain.entities.user import User
from app.application.auth.ports import IUserRepository
from app.domain.exceptions import InvalidCredentialsError

@dataclass
class LoginResult:
    tokens: dict
    user: User

class LoginUseCase:
    def __init__(
        self,
        user_repository: IUserRepository,
        password_hasher: IPasswordHasher,
        token_issuer: ITokenIssuer
    ):
        self._user_repo = user_repository
        self._password_hasher = password_hasher
        self._token_issuer = token_issuer

    def execute(self, email: str, password: str) -> LoginResult:
        user = self._user_repo.find_by_email(Email(email))
        if not user:
            raise UserNotFoundError()

        if not self._password_hasher.verify(password, user.password_hash):
            raise InvalidCredentialsError()

        tokens = self._token_issuer.create_tokens(user.id)
        return LoginResult(tokens=tokens, user=user)
```

### Ports (Interfaces)

**Rules:**
- Define contracts for infrastructure
- Use `ABC` (Abstract Base Class)
- Name format: `I{Noun}{Action}` or `I{Noun}Repository`

**Example:**
```python
from abc import ABC, abstractmethod
from typing import Optional
from app.domain.entities.user import User
from app.domain.value_objects.email import Email

class IUserRepository(ABC):
    @abstractmethod
    def find_by_email(self, email: Email) -> Optional[User]:
        ...

    @abstractmethod
    def save(self, user: User) -> None:
        ...

    @abstractmethod
    def find_by_id(self, user_id: UUID) -> Optional[User]:
        ...
```

## Infrastructure Layer Standards

### Repositories

**Rules:**
- Implement domain ports
- Handle ORM/DB details
- Return domain entities (not ORM models)
- One repository per aggregate root

**Example:**
```python
from sqlalchemy.orm import Session
from app.domain.entities.user import User
from app.application.auth.ports import IUserRepository
from app.infrastructure.database.models.user_model import UserModel

class SqlAlchemyUserRepository(IUserRepository):
    def __init__(self, db_session: Session):
        self._session = db_session

    def find_by_email(self, email: Email) -> Optional[User]:
        model = self._session.query(UserModel).filter_by(
            email=email.value
        ).first()
        return self._to_entity(model) if model else None

    def save(self, user: User) -> None:
        model = self._to_model(user)
        self._session.add(model)
        self._session.commit()

    def _to_entity(self, model: UserModel) -> User:
        return User(
            id=model.id,
            email=Email(model.email),
            password_hash=HashedPassword(model.password_hash),
            is_active=model.is_active
        )

    def _to_model(self, entity: User) -> UserModel:
        return UserModel(
            id=entity.id,
            email=entity.email.value,
            password_hash=entity.password_hash.value,
            is_active=entity.is_active
        )
```

### Database Models

**Rules:**
- SQLAlchemy declarative models
- Map to domain entities (not 1:1 coupling)
- No business logic

**Example:**
```python
from sqlalchemy import Column, String, Boolean
from sqlalchemy.dialects.postgresql import UUID
from uuid import uuid4

from app.infrastructure.database.base import Base

class UserModel(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    email = Column(String(255), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
```

## API Layer Standards

### Routes

**Rules:**
- Thin controllers (no business logic)
- Delegate to use cases
- Handle HTTP concerns only
- Validate with Pydantic schemas

**Example:**
```python
from flask import request, jsonify
from pydantic import ValidationError

from app.application.auth.login_usecase import LoginUseCase

@auth_bp.route("/login", methods=["POST"])
@limiter.limit("5 per minute")
def login():
    try:
        data = LoginRequest(**request.get_json())
    except ValidationError as e:
        return jsonify(ErrorResponse(...).model_dump()), 400

    container = get_container()
    result = container.login_usecase.execute(data.email, data.password)

    return jsonify(LoginResponse(...).model_dump()), 200
```

### Schemas (Pydantic)

**Rules:**
- Separate request/response models
- Name format: `{Entity}{Action}Request/Response`
- Use Pydantic validators for complex validation

**Example:**
```python
from pydantic import BaseModel, Field, EmailStr

class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)

class UserResponse(BaseModel):
    id: str
    email: str
    permissions: list[str]
    roles: list[str]

class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    user: UserResponse
```

## Error Handling

### Exception Hierarchy

```
Exception
├── DomainException (base for all domain errors)
│   ├── AuthenticationError
│   │   ├── InvalidCredentialsError
│   │   └── UserNotFoundError
│   └── ValidationError
│       └── InvalidEmailError
├── ApplicationException
│   └── UseCaseError
└── InfrastructureException
    ├── DatabaseError
    └── ExternalServiceError
```

### Error Responses (API)

**Format:**
```json
{
  "error": "ErrorTypeName",
  "message": "Human-readable description",
  "status_code": 401
}
```

**Mapping:**
- `InvalidCredentialsError` → 401 Unauthorized
- `UserNotFoundError` → 404 Not Found
- `ValidationError` → 400 Bad Request
- `PermissionDeniedError` → 403 Forbidden

## Testing Standards

### Test Organization

**Structure:**
```
tests/
├── unit/
│   ├── domain/
│   ├── application/
│   └── infrastructure/
├── integration/
│   └── test_auth_endpoints.py
└── conftest.py  # Shared fixtures
```

### Test Naming

**Format:** `test_{method}_{scenario}_{expected_result}`

**Examples:**
- `test_login_valid_credentials_returns_tokens()`
- `test_login_invalid_password_raises_error()`
- `test_logout_clears_cookies()`

### Test Structure (AAA Pattern)

**Arrange-Act-Assert:**
```python
def test_login_valid_credentials_returns_tokens(client, db_session):
    # Arrange
    user = create_test_user(email="test@example.com")
    db_session.add(user)
    db_session.commit()

    # Act
    response = client.post("/api/v1/auth/login", json={
        "email": "test@example.com",
        "password": "password123"
    })

    # Assert
    assert response.status_code == 200
    assert "access_token" in response.json
```

### Fixtures

**Rules:**
- Define in `conftest.py`
- Use descriptive names
- Clean up resources

**Example:**
```python
import pytest
from app import create_app

@pytest.fixture
def app():
    app = create_app("testing")
    return app

@pytest.fixture
def client(app):
    return app.test_client()

@pytest.fixture
def db_session(app):
    with app.app_context():
        db.create_all()
        yield db.session
        db.session.remove()
        db.drop_all()
```

## Security Standards

### Password Hashing

**Algorithm:** Argon2id
**Library:** `argon2-cffi`
**Parameters:** Default (time_cost=2, memory_cost=102400, parallelism=8)

### JWT Configuration

**Algorithm:** HS256
**Access Token Expiry:** 30 minutes
**Refresh Token Expiry:** 7 days
**Storage:** Redis blacklist for revocation

### Secrets Management

**Rules:**
- Never commit secrets to git
- Use environment variables
- Validate required secrets at startup

**Example `.env`:**
```bash
DATABASE_URL=postgresql://user:pass@localhost/db
JWT_SECRET_KEY=random-256-bit-key
REDIS_URL=redis://localhost:6379/0
```

## Database Standards

### Migrations

**Tool:** Alembic
**Location:** `migrations/versions/`
**Commands:**
- Generate: `flask db migrate -m "description"`
- Apply: `flask db upgrade`
- Rollback: `flask db downgrade`

### Query Optimization

**Rules:**
- Avoid N+1 queries (use `joinedload`)
- Index foreign keys and frequently queried columns
- Use connection pooling

**Example:**
```python
# Bad (N+1)
users = session.query(User).all()
for user in users:
    print(user.roles)  # Triggers separate query

# Good
from sqlalchemy.orm import joinedload
users = session.query(User).options(joinedload(User.roles)).all()
```

## Dependency Injection

**Location:** `wiring.py`

**Pattern:** Simple DI container
**Purpose:** Decouple layers, enable testing

**Container Components:**
```python
from dataclasses import dataclass

@dataclass
class Container:
    user_repository: IUserRepository
    token_issuer: ITokenIssuer
    password_hasher: IPasswordHasher
    authorization_service: IAuthorizationService
    login_usecase: LoginUseCase
```

**Initialization:** App startup via `create_app()`

## Performance Guidelines

### Caching

**Strategy:** Redis for frequently accessed data
**TTL:** Based on data change frequency

**Example:**
```python
# Cache user permissions (rarely change)
cache_key = f"user:{user_id}:permissions"
permissions = redis.get(cache_key)
if not permissions:
    permissions = db.query(...)
    redis.setex(cache_key, 3600, permissions)
```

### Rate Limiting

**Strategy:** Token bucket (Redis-backed)
**Limits:**
- Default: 100 req/min per IP
- Login: 5 req/min per IP

**Implementation:** Flask-Limiter

## Unresolved Questions

- Async support (Flask 2.0+ async routes vs. Celery for background tasks)
- Database connection pool configuration for high load
- Event sourcing for audit trail
- Logging format and centralization (JSON logs to ELK stack)
