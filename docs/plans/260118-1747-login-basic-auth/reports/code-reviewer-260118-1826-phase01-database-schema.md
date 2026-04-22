# Code Review: Phase 01 Database Schema

**Score: 8.5/10**

## Scope
- Files reviewed: 9
- Focus: Database schema for auth (User, Role, Permission)
- Phase: phase-01-database-schema

## Overall Assessment
Solid implementation following hexagonal architecture. Domain entities cleanly separated from SQLAlchemy models. Uses modern practices (UUID PKs, timezone-aware datetime, Argon2). Minor issues around index naming and missing validation.

---

## Critical Issues
None.

---

## High Priority Findings

### 1. Email Index Not Case-Insensitive
**File:** `app/infrastructure/database/models.py:77`
```python
__table_args__ = (Index("ix_users_email_lower", "email"),)
```
- Index name says "lower" but no `func.lower()` expression
- Will not support case-insensitive lookups efficiently

**Fix:** Use functional index or rely on PostgreSQL CITEXT extension:
```python
from sqlalchemy import func
Index("ix_users_email_lower", func.lower(email))
```

### 2. Password Passed via CLI Args (Seed Script)
**File:** `scripts/seed_auth.py:157`
```python
password = sys.argv[idx + 2]
```
- Password visible in shell history, process list
- Acceptable for dev seed script but document the risk

**Recommendation:** Add note in script docstring warning about CLI exposure.

---

## Medium Priority Findings

### 3. Missing Email Validation in Domain Entity
**File:** `app/domain/entities/user.py:32`
- `User.create()` accepts any string as email
- No format validation before DB insertion

**Recommendation:** Add basic email validation in domain layer:
```python
import re
if not re.match(r'^[^@]+@[^@]+\.[^@]+$', email):
    raise ValueError("Invalid email format")
```

### 4. `datetime.utcnow()` Deprecated
**File:** Plan references `datetime.utcnow()` but implementation uses `datetime.now(timezone.utc)` - good. Consistent across all files.

### 5. No Password Hash Column Length Check
**File:** `app/infrastructure/database/models.py:65`
- Argon2 hashes are ~97 chars typically
- `String(255)` is fine but could be tighter (`String(128)`)

### 6. Missing Composite Index on user_roles
**File:** `app/infrastructure/database/models.py:22-38`
- Primary key on (user_id, role_id) already provides index
- Consider adding reverse index on (role_id) for role-based queries

---

## Low Priority Suggestions

### 7. Domain Entity `__eq__` Not Defined
- `Role.add_permission()` uses `if permission not in self.permissions`
- Works via object identity; consider explicit ID-based equality

### 8. Association Table `assigned_at` Default
**File:** `app/infrastructure/database/models.py:37`
- Uses lambda; correct pattern for SQLAlchemy 2.0

### 9. Consider Adding `__slots__` to Dataclasses
- Minor memory optimization for domain entities

---

## Positive Observations
- Clean separation: Domain entities vs ORM models
- Modern SQLAlchemy 2.0 (`DeclarativeBase`)
- Timezone-aware timestamps (`datetime.now(timezone.utc)`)
- Cascade deletes properly configured
- Proper use of UUID for non-enumerable IDs
- Seed script is idempotent (checks existing records)
- Migration includes proper downgrade path
- Wildcard permission support (`*:*`) for admin role

---

## Security Checklist
| Check | Status |
|-------|--------|
| Password stored as hash only | PASS |
| Argon2 for hashing | PASS |
| UUIDs prevent enumeration | PASS |
| Email lowercased | PASS |
| Cascade deletes | PASS |
| No secrets in code | PASS |

---

## Architecture Compliance
| Pattern | Status |
|---------|--------|
| Hexagonal (domain vs infra) | PASS |
| Domain entities pure Python | PASS |
| ORM in infrastructure layer | PASS |
| Factory methods on entities | PASS |

---

## Recommended Actions
1. **[HIGH]** Fix email index to be truly case-insensitive
2. **[MEDIUM]** Add email format validation in User.create()
3. **[LOW]** Add reverse index on role_permissions(permission_id)
4. **[LOW]** Document CLI password exposure in seed script

---

## Metrics
- Lines of code: ~350
- Domain entities: 3 (User, Role, Permission)
- ORM models: 3 + 2 association tables
- Migration: 1 (reversible)

---

## Task Completion Status
| Task | Status |
|------|--------|
| Domain entity classes | DONE |
| SQLAlchemy models | DONE |
| Many-to-many relationships | DONE |
| Flask-Migrate init | DONE |
| Initial migration created | DONE |
| Seed script | DONE |

**Phase Status:** COMPLETE (pending minor fixes)

---

## Unresolved Questions
1. Should email validation be in domain or application layer?
2. Is CITEXT extension available in target PostgreSQL?
