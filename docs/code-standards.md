# Code Standards

**Last Updated:** 2026-01-18
**Version:** 1.0

## Architecture Principles

### Hexagonal Architecture (Ports & Adapters)

**Core Principle:** Decouple business logic from external concerns

**Layers:**
1. **Domain** - Pure business logic (no framework dependencies)
2. **Application** - Use cases, orchestration
3. **Infrastructure** - External services (DB, Redis, etc.)
4. **API** - HTTP endpoints, request/response handling

**Rules:**
- Domain depends on nothing
- Application depends only on domain
- Infrastructure depends on domain interfaces (ports)
- API depends on application and infrastructure

### Dependency Flow

```
API Layer → Application Layer → Domain Layer
     ↓              ↓
Infrastructure Layer (implements domain ports)
```

**Forbidden:**
- Domain importing from infrastructure
- Domain importing Flask/SQLAlchemy
- Application importing infrastructure implementations directly

## Project Structure

### Frontend (Next.js 16 + React 19)

```
construction-front-end/
├── src/
│   ├── __tests__/           # Test files (Vitest)
│   │   └── setup.test.ts    # Setup verification tests
│   ├── app/                 # Next.js App Router
│   ├── components/          # React components
│   ├── lib/                 # Utility functions
│   └── types/               # TypeScript types
├── public/                  # Static assets
├── package.json             # Dependencies and scripts
├── tsconfig.json            # TypeScript configuration
├── vitest.config.ts         # Vitest test configuration
└── .env                     # Environment variables (not committed)
```

### Backend (Flask)

```
construction-back-end/
├── app/
│   ├── __init__.py              # App factory
│   ├── api/                     # API layer
│   │   └── v1/
│   │       ├── __init__.py
│   │       └── auth/
│   │           ├── __init__.py
│   │           ├── routes.py    # Endpoint definitions
│   │           ├── schemas.py   # Pydantic models
│   │           └── middleware.py
│   ├── application/             # Use cases
│   │   └── auth/
│   │       ├── login_usecase.py
│   │       └── ports.py         # Interfaces
│   ├── domain/                  # Business logic
│   │   ├── entities/            # Aggregate roots
│   │   ├── value_objects/       # Immutable values
│   │   └── exceptions/          # Domain exceptions
│   └── infrastructure/          # External adapters
│       ├── database/
│       │   ├── models/          # SQLAlchemy models
│       │   └── repositories/    # DB access
│       ├── auth/                # JWT, password hashing
│       └── authorization/       # RBAC service
├── config/                      # Configuration
│   └── __init__.py
├── migrations/                  # Alembic migrations
│   └── versions/
├── tests/                       # Test suite
│   ├── test_auth_endpoints.py
│   └── conftest.py
├── wiring.py                    # Dependency injection
├── run.py                       # Entry point
├── pyproject.toml               # Dependencies
└── .env                         # Local config (not committed)
```

## Contents

- [Frontend Code Standards](./code-standards-frontend.md) - Next.js, React, TypeScript, Vitest standards
- [Backend Code Standards](./code-standards-backend.md) - Flask, Python, SQLAlchemy, pytest standards

## Naming Conventions

### Python Files & Modules

**Format:** `snake_case`

**Examples:**
- `login_usecase.py`
- `jwt_token_issuer.py`
- `user_repository.py`

**Rationale:** PEP 8 compliance

### Classes

**Format:** `PascalCase`

**Examples:**
- `LoginUseCase`
- `UserRepository`
- `HashedPassword`

**Interfaces:** Prefix with `I` (e.g., `IUserRepository`, `ITokenIssuer`)

### Functions & Methods

**Format:** `snake_case`

**Examples:**
- `create_access_token()`
- `find_by_email()`
- `verify_password()`

### Constants

**Format:** `UPPER_SNAKE_CASE`

**Examples:**
- `JWT_ALGORITHM = "HS256"`
- `TOKEN_EXPIRY_MINUTES = 30`

### Variables

**Format:** `snake_case`

**Examples:**
- `user_id`
- `access_token`
- `permissions_list`

## Code Organization

### File Size Limits

**Target:** <200 lines per file
**Enforcement:** Soft limit (review during PR)

**Rationale:** Maintainability, readability, testability

**When to split:**
- Multiple use cases in one file → separate files per use case
- Large repository → split into specialized repositories
- God objects → extract value objects, services

### Import Order

**Groups (PEP 8):**
1. Standard library
2. Third-party packages
3. Local application imports

**Example:**
```python
import os
from datetime import timedelta
from typing import Optional

from flask import Flask, jsonify
from sqlalchemy import select

from app.domain.entities.user import User
from app.application.auth.ports import IUserRepository
```

**Spacing:** One blank line between groups

### Module Organization

**Order within file:**
1. Docstring
2. Imports
3. Constants
4. Type definitions
5. Classes
6. Functions

**Example:**
```python
"""User authentication use case."""

import os
from typing import Optional

from app.domain.entities.user import User

JWT_ALGORITHM = "HS256"

class LoginUseCase:
    ...
```

## Typing Standards

### Type Hints

**Rule:** All public functions/methods MUST have type hints

**Example:**
```python
def create_access_token(
    user_id: UUID,
    claims: dict[str, Any]
) -> str:
    ...
```

**Exceptions:** Private methods (optional but recommended)

### Return Types

**Rule:** Always specify return type, including `None`

**Examples:**
```python
def find_by_id(self, user_id: UUID) -> Optional[User]:
    ...

def save(self, user: User) -> None:
    ...
```

### Generic Types

**Use:** `from typing import List, Dict, Optional` (Python <3.9)
**Use:** `list`, `dict`, `str | None` (Python 3.9+)

**Example:**
```python
# Python 3.9+
def get_permissions(self, user_id: UUID) -> list[str]:
    ...

# Python 3.8
from typing import List
def get_permissions(self, user_id: UUID) -> List[str]:
    ...
```

## Code Quality Tools

### Linting

**Tool:** Ruff
**Config:** `pyproject.toml`
**Command:** `ruff check .`

**Rules:**
- Line length: 100 characters
- Import sorting: `isort` compatible
- PEP 8 compliance

### Type Checking

**Tool:** mypy
**Config:** `pyproject.toml`
**Command:** `mypy app/`

**Strictness:** Medium (allow implicit optional)

### Formatting

**Tool:** Ruff formatter (or Black)
**Command:** `ruff format .`
**Line Length:** 100

## Documentation Standards

### Docstrings

**Format:** Google style

**Example:**
```python
def create_access_token(user_id: UUID, claims: dict) -> str:
    """
    Create JWT access token for authenticated user.

    Args:
        user_id: Unique user identifier
        claims: Additional JWT claims (permissions, roles)

    Returns:
        Signed JWT access token string

    Raises:
        TokenCreationError: If signing fails
    """
    ...
```

### Comments

**When to use:**
- Complex algorithms
- Non-obvious business rules
- Workarounds for external library bugs

**When NOT to use:**
- Obvious code (`# Increment counter`)
- Restating code logic
- Outdated comments (delete instead)

## Version Control

### Commit Messages

**Format:** Conventional Commits

**Structure:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `refactor` - Code restructuring
- `docs` - Documentation
- `test` - Add/update tests
- `chore` - Maintenance

**Example:**
```
feat(auth): implement login endpoint

- Add LoginUseCase with credential validation
- Create JWT token issuer with Redis blacklist
- Add rate limiting (5 req/min)

Closes #123
```

### Branch Naming

**Format:** `{type}/{description}`

**Examples:**
- `feat/user-registration`
- `fix/login-csrf-token`
- `refactor/repository-pattern`

## Performance Guidelines

### Database Queries

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
users = session.query(User).options(joinedload(User.roles)).all()
```

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

## Unresolved Standards Questions

- Async support (Flask 2.0+ async routes vs. Celery for background tasks)
- API pagination strategy (cursor vs. offset)
- Logging format and centralization (JSON logs to ELK stack)
