# Code Review Report: Phase 02 Backend Auth Core

**Date:** 2026-01-18
**Reviewer:** code-reviewer agent
**Phase:** Phase 02 - Backend Auth Core
**Plan:** `/Users/sweet-home/Works/construction/docs/plans/260118-1747-login-basic-auth/`

---

## Code Review Summary

### Scope
- Files reviewed: 13 files
- Lines of code analyzed: ~450 lines
- Review focus: Phase 02 Backend Auth Core implementation

### Files Reviewed
1. `app/domain/exceptions/auth_exceptions.py`
2. `app/domain/value_objects/credentials.py`
3. `app/application/ports/password_hasher_port.py`
4. `app/application/ports/token_issuer_port.py`
5. `app/application/ports/session_manager_port.py`
6. `app/application/ports/user_repository_port.py`
7. `app/domain/services/auth_service.py`
8. `app/domain/services/authorization_service.py`
9. `app/infrastructure/adapters/argon2_password_hasher.py`
10. `app/infrastructure/adapters/jwt_token_issuer.py`
11. `app/application/usecases/login_usecase.py`
12. `app/application/usecases/logout_usecase.py`
13. `wiring.py`

---

## Overall Assessment

**Score: 8.5/10**

Implementation follows hexagonal architecture pattern well. Clean separation between domain, application, and infrastructure layers. Ports use Python Protocol for structural typing. Minor issues with incomplete implementation and some security enhancements needed.

---

## Critical Issues

**None found.**

---

## High Priority Findings

### H1. Missing `flask_session_manager.py` Adapter
**Location:** `app/infrastructure/adapters/`
**Issue:** Plan specifies `flask_session_manager.py` but file not created
**Impact:** SessionManagerPort has no implementation
**Fix:** Create adapter or remove from Phase 02 scope if deferred to Phase 03

### H2. Token Revocation Not Implemented
**Location:** `app/infrastructure/adapters/jwt_token_issuer.py:47-50`
```python
def revoke_token(self, jti: str) -> None:
    """Add token to blacklist. Implemented in Phase 03 with Redis."""
    # TODO: Implement Redis blacklist in Phase 03
    pass
```
**Issue:** LogoutUseCase calls `revoke_token()` which does nothing
**Impact:** Logout does not actually invalidate tokens until Phase 03
**Note:** Acceptable if Phase 03 implements Redis blacklist as planned

### H3. UserRepositoryPort Uses `Any` Type
**Location:** `app/application/ports/user_repository_port.py`
```python
def find_by_id(self, user_id: UUID) -> Optional[Any]:
def find_by_email(self, email: str) -> Optional[Any]:
def save(self, user: Any) -> Any:
```
**Issue:** Port methods use `Any` instead of User entity type
**Impact:** Loses type safety, IDE autocomplete, domain contract clarity
**Fix:** Import User entity or define UserProtocol for structural typing

---

## Medium Priority Improvements

### M1. AuthService Leaks User Existence via Exception Type
**Location:** `app/domain/services/auth_service.py:42-43`
```python
if not user:
    raise UserNotFoundError(f"User not found: {email}")
```
**Issue:** Separate `UserNotFoundError` vs `InvalidCredentialsError` allows enumeration
**Recommendation:** Use single `InvalidCredentialsError` for both cases in API layer
**Note:** Current approach OK for internal use if API layer consolidates errors

### M2. Authorization Service Calls Repository Twice
**Location:** `app/domain/services/authorization_service.py:27-29`
```python
def has_permission(self, user_id: UUID, permission: str) -> bool:
    user_perms = self.get_user_permissions(user_id)  # calls find_by_id
```
**Issue:** `has_role()` fetches user, `has_permission()` also fetches user
**Impact:** Multiple DB queries for same authorization check
**Fix:** Accept user object parameter or cache within request context

### M3. Password Value Object Not Used
**Location:** `app/domain/value_objects/credentials.py`
**Issue:** Password VO exists but AuthService accepts plain `str`
**Impact:** Validation bypassed; VO unused
**Recommendation:** Either use VO in service layer or document as DTO-only validation

### M4. JWTTokenIssuer Uses Wrong Exception Import
**Location:** `app/infrastructure/adapters/jwt_token_issuer.py:8`
```python
from jwt.exceptions import PyJWTError
```
**Issue:** Using `jwt.exceptions.PyJWTError` but Flask-JWT-Extended may throw different exceptions
**Impact:** Some JWT errors may not be caught
**Fix:** Also catch `flask_jwt_extended.exceptions.JWTDecodeError` or generic `Exception`

---

## Low Priority Suggestions

### L1. Argon2 Could Check for Rehash Need
**Location:** `app/infrastructure/adapters/argon2_password_hasher.py`
**Suggestion:** Add `needs_rehash()` method for parameter upgrades
```python
def needs_rehash(self, password_hash: str) -> bool:
    return self._hasher.check_needs_rehash(password_hash)
```

### L2. LoginResult Could Include Token Expiry
**Location:** `app/application/usecases/login_usecase.py`
**Suggestion:** Add `expires_at` field for frontend to know when to refresh

### L3. Container Could Use Factory Pattern
**Location:** `wiring.py`
**Suggestion:** Use `get_auth_service()` factory methods for lazy initialization

---

## Positive Observations

1. **Excellent Hexagonal Architecture** - Clean separation of domain/application/infrastructure layers
2. **Protocol Usage** - Ports use `typing.Protocol` for structural typing (Pythonic)
3. **Immutable Value Objects** - `Email` and `Password` use `frozen=True, slots=True`
4. **Authorization Service** - Well-designed RBAC with wildcard support (`*:*`, `resource:*`)
5. **Argon2 Configuration** - Secure defaults (2 iterations, 64MB memory)
6. **Clean Use Cases** - Single responsibility, orchestrate domain services
7. **Proper Exception Hierarchy** - AuthenticationError vs AuthorizationError base classes
8. **Email Normalization** - Both VO and service normalize email (lowercase, strip)

---

## Task Completion Analysis

### Plan Todo List Status

| Task | Status | Notes |
|------|--------|-------|
| Create domain exceptions module | DONE | `auth_exceptions.py` complete |
| Create value objects (Email, Password) | DONE | `credentials.py` with validation |
| Create PasswordHasherPort interface | DONE | Protocol-based |
| Create TokenIssuerPort interface | DONE | Protocol-based |
| Create SessionManagerPort interface | DONE | Protocol-based |
| Implement AuthService domain service | DONE | authenticate(), hash_password() |
| Implement AuthorizationService | DONE | RBAC with wildcard support |
| Create Argon2PasswordHasher adapter | DONE | Secure parameters |
| Create JWTTokenIssuer adapter | DONE | TODO: revoke_token() |
| Create LoginUseCase | DONE | Returns LoginResult |
| Update wiring.py with new ports | DONE | Container configured |
| Write unit tests for domain services | NOT DONE | Deferred to Phase 06 |

**Completion: 11/12 tasks (92%)**

### Missing from Plan
- `flask_session_manager.py` adapter listed but not created

---

## Recommended Actions

1. **[HIGH]** Create `flask_session_manager.py` OR update plan to defer to Phase 03
2. **[HIGH]** Consider typing UserRepositoryPort with User entity/protocol
3. **[MEDIUM]** Ensure API layer consolidates auth errors to prevent enumeration
4. **[MEDIUM]** Verify JWT exception handling covers Flask-JWT-Extended exceptions
5. **[LOW]** Add token expiry to LoginResult for frontend convenience

---

## Metrics

| Metric | Value |
|--------|-------|
| Compilation | PASS |
| Type Hints | Good (except UserRepositoryPort) |
| Documentation | Adequate docstrings |
| Layer Separation | Excellent |
| Security Posture | Good (Argon2, proper exceptions) |

---

## Unresolved Questions

1. Is `flask_session_manager.py` intentionally deferred to Phase 03?
2. Should unit tests be added now or in Phase 06?
3. Will Redis token blacklist be implemented in Phase 03 as noted in TODO?
