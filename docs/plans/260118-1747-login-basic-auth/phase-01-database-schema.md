# Phase 01: Database Schema

## Context Links
- [Parent Plan](plan.md)
- [Flask Auth Research](research/researcher-01-flask-auth-report.md)

## Overview
| Field | Value |
|-------|-------|
| Priority | P1 - Critical |
| Status | complete |
| Review Status | reviewed (8.5/10) |
| Estimated Effort | 2h |

Create database tables for User, Role, Permission with proper relationships for RBAC. Set up migrations using Flask-Migrate/Alembic.

## Key Insights
- Argon2 for password hashing (GPU-resistant, modern standard)
- Many-to-many: User↔Role, Role↔Permission
- Permission format: `resource:action` (e.g., `project:create`)
- UUID primary keys for security (non-sequential)

## Requirements

### Functional
- User table with email, password_hash, is_active
- Role table with name, description
- Permission table with name, resource, action
- Association tables for relationships

### Non-Functional
- PostgreSQL compatibility
- Indexed email field (unique, case-insensitive)
- Cascade delete for associations
- Timestamps (created_at, updated_at)

## Architecture

### Entity Relationship Diagram
```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    User      │     │     Role     │     │  Permission  │
├──────────────┤     ├──────────────┤     ├──────────────┤
│ id (UUID)    │     │ id (UUID)    │     │ id (UUID)    │
│ email        │◄────│ name         │◄────│ name         │
│ password_hash│  M:M│ description  │  M:M│ resource     │
│ is_active    │     │ created_at   │     │ action       │
│ created_at   │     └──────────────┘     │ created_at   │
│ updated_at   │                          └──────────────┘
└──────────────┘
        │                    │
        └────────┬───────────┘
                 ▼
        ┌──────────────┐     ┌──────────────┐
        │  user_roles  │     │role_perms    │
        ├──────────────┤     ├──────────────┤
        │ user_id (FK) │     │ role_id (FK) │
        │ role_id (FK) │     │ perm_id (FK) │
        │ assigned_at  │     └──────────────┘
        └──────────────┘
```

## Related Code Files

### Files to Create
- `construction-back-end/app/domain/entities/user.py`
- `construction-back-end/app/domain/entities/role.py`
- `construction-back-end/app/domain/entities/permission.py`
- `construction-back-end/app/infrastructure/database/models.py`
- `construction-back-end/migrations/versions/001_create_auth_tables.py`

### Files to Modify
- `construction-back-end/pyproject.toml` (add SQLAlchemy, Flask-Migrate, argon2-cffi)
- `construction-back-end/wiring.py` (add database configuration)

## Implementation Steps

### Step 1: Add Dependencies
```bash
# In construction-back-end/
uv add sqlalchemy flask-migrate argon2-cffi psycopg2-binary alembic
```

Update `pyproject.toml`:
```toml
dependencies = [
    # ... existing
    "sqlalchemy>=2.0.0",
    "flask-migrate>=4.0.0",
    "argon2-cffi>=23.1.0",
    "psycopg2-binary>=2.9.0",
]
```

### Step 2: Create Domain Entities

**`app/domain/entities/user.py`**
```python
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional
from uuid import UUID, uuid4

@dataclass
class User:
    id: UUID
    email: str
    password_hash: str
    is_active: bool = True
    created_at: datetime = None
    updated_at: datetime = None
    roles: List["Role"] = None

    @classmethod
    def create(cls, email: str, password_hash: str) -> "User":
        return cls(
            id=uuid4(),
            email=email.lower(),
            password_hash=password_hash,
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
            roles=[]
        )
```

### Step 3: Create SQLAlchemy Models

**`app/infrastructure/database/models.py`**
```python
from datetime import datetime
from uuid import uuid4
from sqlalchemy import (
    Column, String, Boolean, DateTime, ForeignKey, Table, Index
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship, declarative_base

Base = declarative_base()

# Association tables
user_roles = Table(
    'user_roles', Base.metadata,
    Column('user_id', UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
    Column('role_id', UUID(as_uuid=True), ForeignKey('roles.id', ondelete='CASCADE'), primary_key=True),
    Column('assigned_at', DateTime, default=datetime.utcnow)
)

role_permissions = Table(
    'role_permissions', Base.metadata,
    Column('role_id', UUID(as_uuid=True), ForeignKey('roles.id', ondelete='CASCADE'), primary_key=True),
    Column('permission_id', UUID(as_uuid=True), ForeignKey('permissions.id', ondelete='CASCADE'), primary_key=True)
)

class UserModel(Base):
    __tablename__ = 'users'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    roles = relationship('RoleModel', secondary=user_roles, back_populates='users')

    __table_args__ = (
        Index('ix_users_email_lower', 'email'),
    )

class RoleModel(Base):
    __tablename__ = 'roles'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    name = Column(String(50), unique=True, nullable=False)
    description = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow)

    users = relationship('UserModel', secondary=user_roles, back_populates='roles')
    permissions = relationship('PermissionModel', secondary=role_permissions, back_populates='roles')

class PermissionModel(Base):
    __tablename__ = 'permissions'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    name = Column(String(100), unique=True, nullable=False)  # e.g., 'project:create'
    resource = Column(String(50), nullable=False)  # e.g., 'project'
    action = Column(String(50), nullable=False)    # e.g., 'create'
    created_at = Column(DateTime, default=datetime.utcnow)

    roles = relationship('RoleModel', secondary=role_permissions, back_populates='permissions')
```

### Step 4: Initialize Flask-Migrate

**Update `app/__init__.py`**
```python
from flask_migrate import Migrate
from app.infrastructure.database.models import Base

db = None
migrate = Migrate()

def create_app(config_class: type = Config) -> Flask:
    # ... existing code

    # Initialize database
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    engine = create_engine(app.config['DATABASE_URL'])
    Base.metadata.bind = engine

    # Initialize migrations
    migrate.init_app(app, Base)

    return app
```

### Step 5: Create Initial Migration
```bash
cd construction-back-end
uv run flask db init
uv run flask db migrate -m "Create auth tables"
uv run flask db upgrade
```

### Step 6: Seed Default Roles/Permissions
```python
# scripts/seed_auth.py
def seed_roles_permissions():
    roles = [
        {"name": "admin", "description": "Full system access"},
        {"name": "manager", "description": "Project management access"},
        {"name": "user", "description": "Basic user access"}
    ]

    permissions = [
        {"name": "project:create", "resource": "project", "action": "create"},
        {"name": "project:read", "resource": "project", "action": "read"},
        {"name": "project:update", "resource": "project", "action": "update"},
        {"name": "project:delete", "resource": "project", "action": "delete"},
        {"name": "user:create", "resource": "user", "action": "create"},
        {"name": "user:read", "resource": "user", "action": "read"},
        {"name": "user:update", "resource": "user", "action": "update"},
        {"name": "user:delete", "resource": "user", "action": "delete"},
    ]
    # Insert into DB...
```

## Todo List

- [x] Add SQLAlchemy, Flask-Migrate, argon2-cffi dependencies
- [x] Create domain entity classes (User, Role, Permission)
- [x] Create SQLAlchemy models with relationships
- [x] Initialize Flask-Migrate
- [x] Create initial migration
- [x] Run migration on PostgreSQL
- [x] Create seed script for default roles/permissions
- [x] Test database schema

## Success Criteria

- [ ] All tables created in PostgreSQL
- [ ] Foreign key relationships work correctly
- [ ] Migration can be rolled back
- [ ] Default roles/permissions seeded
- [ ] Email uniqueness constraint enforced

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Migration conflicts | Low | Medium | Test on fresh DB first |
| PostgreSQL compatibility | Low | High | Use standard SQLAlchemy types |
| UUID performance | Low | Low | Add proper indexes |

## Security Considerations

- Password stored as Argon2 hash only
- UUIDs prevent enumeration attacks
- Cascade delete prevents orphaned records
- Email stored lowercase for consistency

## Next Steps

After this phase:
→ [Phase 02: Backend Auth Core](phase-02-backend-auth-core.md)
