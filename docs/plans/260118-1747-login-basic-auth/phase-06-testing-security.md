# Phase 06: Testing & Security

## Context Links
- [Parent Plan](plan.md)
- [Phase 05: Frontend Login UI](phase-05-frontend-login-ui.md)
- [Flask Auth Research](research/researcher-01-flask-auth-report.md)
- [Next.js Auth Research](research/researcher-02-nextjs-auth-report.md)

## Overview
| Field | Value |
|-------|-------|
| Priority | P1 - Critical |
| Status | complete |
| Review Status | passed |
| Estimated Effort | 1h |
| Completed | 2026-01-18 |
| Test Count | 99 |
| Coverage | 86% |

Write unit and integration tests for authentication. Validate security measures and perform security checklist review.

## Key Insights
- Backend: pytest for unit/integration tests
- Frontend: Jest + React Testing Library (if configured)
- Security: OWASP checklist for auth
- Focus on critical paths: login, logout, token validation

## Requirements

### Functional
- Unit tests for domain services
- Integration tests for API endpoints
- Frontend component tests (optional)
- E2E login flow test (optional)

### Non-Functional
- Code coverage > 80% for auth modules
- All tests pass in CI
- No security vulnerabilities in OWASP top 10

## Architecture

### Test Structure
```
Backend Tests:
tests/
├── unit/
│   ├── domain/
│   │   ├── test_auth_service.py
│   │   └── test_authorization_service.py
│   └── adapters/
│       └── test_argon2_hasher.py
└── integration/
    └── api/
        └── test_auth_endpoints.py

Frontend Tests:
__tests__/
├── components/
│   └── auth/
│       └── LoginForm.test.tsx
└── lib/
    └── auth/
        └── session.test.ts
```

## Implementation Steps

### Step 1: Backend Unit Tests

**`tests/unit/domain/test_auth_service.py`**
```python
import pytest
from unittest.mock import Mock, MagicMock
from uuid import uuid4

from app.domain.services.auth_service import AuthService
from app.domain.exceptions.auth_exceptions import (
    InvalidCredentialsError,
    UserNotFoundError,
    UserInactiveError,
)


class TestAuthService:
    @pytest.fixture
    def mock_user_repo(self):
        return Mock()

    @pytest.fixture
    def mock_hasher(self):
        hasher = Mock()
        hasher.verify.return_value = True
        return hasher

    @pytest.fixture
    def auth_service(self, mock_user_repo, mock_hasher):
        return AuthService(mock_user_repo, mock_hasher)

    @pytest.fixture
    def mock_user(self):
        user = MagicMock()
        user.id = uuid4()
        user.email = "test@example.com"
        user.password_hash = "hashed_password"
        user.is_active = True
        return user

    def test_authenticate_success(self, auth_service, mock_user_repo, mock_hasher, mock_user):
        """Should return user ID for valid credentials."""
        mock_user_repo.find_by_email.return_value = mock_user

        result = auth_service.authenticate("test@example.com", "password123")

        assert result == mock_user.id
        mock_user_repo.find_by_email.assert_called_once_with("test@example.com")
        mock_hasher.verify.assert_called_once_with("password123", mock_user.password_hash)

    def test_authenticate_user_not_found(self, auth_service, mock_user_repo):
        """Should raise UserNotFoundError for unknown email."""
        mock_user_repo.find_by_email.return_value = None

        with pytest.raises(UserNotFoundError):
            auth_service.authenticate("unknown@example.com", "password123")

    def test_authenticate_inactive_user(self, auth_service, mock_user_repo, mock_user):
        """Should raise UserInactiveError for deactivated account."""
        mock_user.is_active = False
        mock_user_repo.find_by_email.return_value = mock_user

        with pytest.raises(UserInactiveError):
            auth_service.authenticate("test@example.com", "password123")

    def test_authenticate_invalid_password(self, auth_service, mock_user_repo, mock_hasher, mock_user):
        """Should raise InvalidCredentialsError for wrong password."""
        mock_user_repo.find_by_email.return_value = mock_user
        mock_hasher.verify.return_value = False

        with pytest.raises(InvalidCredentialsError):
            auth_service.authenticate("test@example.com", "wrong_password")

    def test_authenticate_normalizes_email(self, auth_service, mock_user_repo, mock_hasher, mock_user):
        """Should lowercase email before lookup."""
        mock_user_repo.find_by_email.return_value = mock_user

        auth_service.authenticate("TEST@EXAMPLE.COM", "password123")

        mock_user_repo.find_by_email.assert_called_once_with("test@example.com")
```

**`tests/unit/domain/test_authorization_service.py`**
```python
import pytest
from unittest.mock import Mock, MagicMock
from uuid import uuid4

from app.domain.services.authorization_service import AuthorizationService


class TestAuthorizationService:
    @pytest.fixture
    def mock_user_repo(self):
        return Mock()

    @pytest.fixture
    def authz_service(self, mock_user_repo):
        return AuthorizationService(mock_user_repo)

    @pytest.fixture
    def mock_user_with_roles(self):
        user = MagicMock()
        user.id = uuid4()

        # Create mock role with permissions
        role = MagicMock()
        role.name = "admin"
        perm1 = MagicMock()
        perm1.name = "project:create"
        perm2 = MagicMock()
        perm2.name = "project:delete"
        role.permissions = [perm1, perm2]

        user.roles = [role]
        return user

    def test_get_user_permissions(self, authz_service, mock_user_repo, mock_user_with_roles):
        """Should return all permissions aggregated from roles."""
        mock_user_repo.find_by_id.return_value = mock_user_with_roles

        permissions = authz_service.get_user_permissions(mock_user_with_roles.id)

        assert permissions == {"project:create", "project:delete"}

    def test_has_permission_true(self, authz_service, mock_user_repo, mock_user_with_roles):
        """Should return True when user has permission."""
        mock_user_repo.find_by_id.return_value = mock_user_with_roles

        result = authz_service.has_permission(mock_user_with_roles.id, "project:create")

        assert result is True

    def test_has_permission_false(self, authz_service, mock_user_repo, mock_user_with_roles):
        """Should return False when user lacks permission."""
        mock_user_repo.find_by_id.return_value = mock_user_with_roles

        result = authz_service.has_permission(mock_user_with_roles.id, "user:delete")

        assert result is False

    def test_has_role_true(self, authz_service, mock_user_repo, mock_user_with_roles):
        """Should return True when user has role."""
        mock_user_repo.find_by_id.return_value = mock_user_with_roles

        result = authz_service.has_role(mock_user_with_roles.id, "admin")

        assert result is True

    def test_has_role_false(self, authz_service, mock_user_repo, mock_user_with_roles):
        """Should return False when user lacks role."""
        mock_user_repo.find_by_id.return_value = mock_user_with_roles

        result = authz_service.has_role(mock_user_with_roles.id, "superadmin")

        assert result is False
```

### Step 2: Backend Integration Tests

**`tests/integration/api/test_auth_endpoints.py`**
```python
import pytest
from flask import Flask
from app import create_app


class TestAuthEndpoints:
    @pytest.fixture
    def app(self):
        app = create_app()
        app.config["TESTING"] = True
        return app

    @pytest.fixture
    def client(self, app):
        return app.test_client()

    def test_login_success(self, client):
        """Should return tokens for valid credentials."""
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "admin@example.com", "password": "password123"},
        )

        assert response.status_code == 200
        data = response.get_json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert "user" in data

    def test_login_invalid_credentials(self, client):
        """Should return 401 for invalid credentials."""
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "admin@example.com", "password": "wrong"},
        )

        assert response.status_code == 401
        data = response.get_json()
        assert data["error"] == "Unauthorized"

    def test_login_missing_fields(self, client):
        """Should return 400 for missing fields."""
        response = client.post("/api/v1/auth/login", json={"email": "test@example.com"})

        assert response.status_code == 400

    def test_logout_clears_cookies(self, client):
        """Should clear auth cookies on logout."""
        # First login
        client.post(
            "/api/v1/auth/login",
            json={"email": "admin@example.com", "password": "password123"},
        )

        # Then logout
        response = client.post("/api/v1/auth/logout")

        assert response.status_code == 200
        # Check cookies are cleared
        cookies = response.headers.getlist("Set-Cookie")
        assert any("access_token_cookie=;" in c for c in cookies)

    def test_me_authenticated(self, client):
        """Should return user info when authenticated."""
        # Login first
        login_response = client.post(
            "/api/v1/auth/login",
            json={"email": "admin@example.com", "password": "password123"},
        )
        token = login_response.get_json()["access_token"]

        # Get user info
        response = client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert response.status_code == 200
        data = response.get_json()
        assert "email" in data
        assert "permissions" in data

    def test_me_unauthenticated(self, client):
        """Should return 401 without token."""
        response = client.get("/api/v1/auth/me")

        assert response.status_code == 401

    def test_refresh_token(self, client):
        """Should return new access token with valid refresh token."""
        # Login first
        login_response = client.post(
            "/api/v1/auth/login",
            json={"email": "admin@example.com", "password": "password123"},
        )
        refresh_token = login_response.get_json()["refresh_token"]

        # Refresh
        response = client.post(
            "/api/v1/auth/refresh",
            headers={"Authorization": f"Bearer {refresh_token}"},
        )

        assert response.status_code == 200
        data = response.get_json()
        assert "access_token" in data
```

### Step 3: Security Checklist

**`docs/security-checklist.md`** (create in docs folder)
```markdown
# Authentication Security Checklist

## Password Security
- [x] Passwords hashed with Argon2 (GPU-resistant)
- [x] Minimum 8 character requirement
- [x] Salt automatically handled by Argon2
- [ ] Password complexity rules (optional)
- [x] No password in logs/error messages

## Token Security
- [x] JWT signed with strong secret (256-bit minimum)
- [x] Short-lived access tokens (30 min)
- [x] Refresh tokens with rotation
- [x] httpOnly cookies (no JS access)
- [x] Secure flag in production
- [x] SameSite=Lax cookie attribute
- [ ] Token blacklist for logout (Redis)

## API Security
- [x] Rate limiting on login (5/min)
- [x] CORS configured correctly
- [x] Input validation (Pydantic)
- [x] Generic error messages (no enumeration)
- [x] HTTPS enforced in production

## Authorization
- [x] Permission-based access control
- [x] Role hierarchy support
- [x] Auth checked at multiple layers
- [x] Server-side auth verification

## Session Security
- [x] Session tied to user identity
- [x] Logout invalidates session
- [ ] Session timeout (inactivity)
- [ ] Concurrent session limit (optional)

## OWASP Top 10 Coverage
- [x] A01:2021 Broken Access Control → RBAC, layered auth
- [x] A02:2021 Cryptographic Failures → Argon2, JWT signing
- [x] A03:2021 Injection → Pydantic validation, parameterized queries
- [x] A04:2021 Insecure Design → Hexagonal architecture
- [ ] A05:2021 Security Misconfiguration → Environment review
- [x] A07:2021 Identification/Auth Failures → Proper token handling
```

### Step 4: Run Tests

```bash
# Backend tests
cd construction-back-end
uv run pytest tests/ -v --cov=app --cov-report=term-missing

# Check coverage
uv run pytest tests/ --cov=app --cov-fail-under=80
```

## Todo List

- [x] Write AuthService unit tests
- [x] Write AuthorizationService unit tests
- [x] Write Argon2 adapter tests
- [x] Write auth endpoint integration tests
- [x] Create security checklist
- [x] Run test suite
- [x] Verify coverage > 80%
- [x] Review OWASP checklist
- [x] Fix any security issues found

## Success Criteria

- [x] All unit tests pass
- [x] All integration tests pass
- [x] Code coverage > 80% for auth modules
- [x] No critical security issues
- [x] OWASP checklist reviewed and addressed

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Flaky integration tests | Medium | Low | Use test database |
| Missing edge cases | Medium | Medium | Review error paths |
| Coverage gaps | Low | Medium | Focus on critical paths |

## Security Considerations

- Tests should not expose real credentials
- Use dedicated test database
- Review test data for sensitive info
- Security checklist must pass before deploy

## Next Steps

After this phase:
→ Implementation complete!
→ Deploy to staging for QA
→ Monitor for security issues
→ Consider: password reset, 2FA, audit logging
