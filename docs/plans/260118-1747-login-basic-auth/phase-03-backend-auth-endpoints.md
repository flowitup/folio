# Phase 03: Backend Auth Endpoints

## Context Links
- [Parent Plan](plan.md)
- [Phase 02: Backend Auth Core](phase-02-backend-auth-core.md)
- [Flask Auth Research](research/researcher-01-flask-auth-report.md)

## Overview
| Field | Value |
|-------|-------|
| Priority | P1 - Critical |
| Status | complete |
| Completed | 2026-01-18 |
| Review Status | reviewed (8.5/10, user approved) |
| Test Results | 58 tests passed, 85% coverage |
| Estimated Effort | 2h |

Create REST API endpoints for authentication: login, logout, refresh token, and current user. Implement auth middleware/decorators for protected routes.

## Key Insights
- Blueprint for `/api/v1/auth/*` routes
- Pydantic schemas for request/response validation
- Dual auth: JWT (Authorization header) + Session (cookies)
- Rate limiting on login endpoint
- Auth decorators for protected routes

## Requirements

### Functional
- `POST /api/v1/auth/login` - Authenticate and return tokens
- `POST /api/v1/auth/logout` - Invalidate session/token
- `POST /api/v1/auth/refresh` - Refresh access token
- `GET /api/v1/auth/me` - Get current user info

### Non-Functional
- JSON request/response format
- Proper HTTP status codes (200, 400, 401, 403)
- Rate limiting (5 attempts per minute)
- CORS configured for frontend origin

## Architecture

### API Flow
```
Client Request
     │
     ▼
┌─────────────────┐
│ Auth Blueprint  │  /api/v1/auth/*
├─────────────────┤
│ Rate Limiter    │  5 req/min on login
├─────────────────┤
│ Pydantic Schema │  Validate input
├─────────────────┤
│ Use Case Layer  │  LoginUseCase, etc.
├─────────────────┤
│ Domain Services │  AuthService
└─────────────────┘
     │
     ▼
JSON Response + Cookies
```

## Related Code Files

### Files to Create
- `app/api/v1/auth/__init__.py` (auth blueprint)
- `app/api/v1/auth/routes.py` (route handlers)
- `app/api/v1/auth/schemas.py` (Pydantic models)
- `app/api/v1/auth/middleware.py` (auth decorators)
- `app/infrastructure/rate_limiter.py` (rate limiting)

### Files to Modify
- `app/__init__.py` (register auth blueprint, JWT config)
- `app/api/v1/__init__.py` (import auth routes)
- `config/__init__.py` (add JWT settings)

## Implementation Steps

### Step 1: Update Config

**`config/__init__.py`**
```python
import os
from datetime import timedelta

class Config:
    # ... existing

    # JWT Configuration
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "dev-jwt-secret")
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(minutes=30)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=7)
    JWT_TOKEN_LOCATION = ["headers", "cookies"]
    JWT_COOKIE_SECURE = os.environ.get("FLASK_ENV") == "production"
    JWT_COOKIE_CSRF_PROTECT = True
    JWT_COOKIE_SAMESITE = "Lax"

    # Rate Limiting
    RATELIMIT_STORAGE_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/1")
    RATELIMIT_DEFAULT = "100/minute"
    RATELIMIT_LOGIN = "5/minute"
```

### Step 2: Create Pydantic Schemas

**`app/api/v1/auth/schemas.py`**
```python
from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from uuid import UUID

class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)

class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int = 1800  # 30 minutes
    user: "UserResponse"

class UserResponse(BaseModel):
    id: UUID
    email: str
    permissions: List[str]
    roles: List[str]

class RefreshRequest(BaseModel):
    refresh_token: str

class RefreshResponse(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int = 1800

class ErrorResponse(BaseModel):
    error: str
    message: str
    status_code: int

class LogoutResponse(BaseModel):
    message: str = "Successfully logged out"
```

### Step 3: Create Auth Blueprint

**`app/api/v1/auth/__init__.py`**
```python
from flask import Blueprint

auth_bp = Blueprint("auth", __name__, url_prefix="/auth")

from app.api.v1.auth import routes  # noqa: E402, F401
```

**`app/api/v1/auth/routes.py`**
```python
from flask import jsonify, request, make_response
from flask_jwt_extended import (
    jwt_required, get_jwt_identity, get_jwt,
    set_access_cookies, set_refresh_cookies, unset_jwt_cookies
)
from pydantic import ValidationError

from app.api.v1.auth import auth_bp
from app.api.v1.auth.schemas import (
    LoginRequest, LoginResponse, RefreshResponse,
    UserResponse, ErrorResponse, LogoutResponse
)
from app.domain.exceptions.auth_exceptions import (
    InvalidCredentialsError, UserNotFoundError, UserInactiveError
)
from wiring import get_container

@auth_bp.route("/login", methods=["POST"])
def login():
    """
    Authenticate user and return tokens.

    Request: { "email": "user@example.com", "password": "********" }
    Response: { "access_token": "...", "refresh_token": "...", "user": {...} }
    """
    try:
        data = LoginRequest(**request.get_json())
    except ValidationError as e:
        return jsonify(ErrorResponse(
            error="ValidationError",
            message=str(e),
            status_code=400
        ).model_dump()), 400

    container = get_container()
    login_usecase = container.login_usecase

    try:
        result = login_usecase.execute(data.email, data.password)
    except (InvalidCredentialsError, UserNotFoundError):
        return jsonify(ErrorResponse(
            error="Unauthorized",
            message="Invalid email or password",
            status_code=401
        ).model_dump()), 401
    except UserInactiveError:
        return jsonify(ErrorResponse(
            error="Forbidden",
            message="Account is deactivated",
            status_code=403
        ).model_dump()), 403

    # Get user details for response
    user_repo = container.user_repository
    user = user_repo.find_by_id(result.user_id)

    response_data = LoginResponse(
        access_token=result.access_token,
        refresh_token=result.refresh_token,
        user=UserResponse(
            id=user.id,
            email=user.email,
            permissions=result.permissions,
            roles=[r.name for r in user.roles]
        )
    )

    response = make_response(jsonify(response_data.model_dump()))

    # Set cookies for browser clients
    set_access_cookies(response, result.access_token)
    set_refresh_cookies(response, result.refresh_token)

    return response

@auth_bp.route("/logout", methods=["POST"])
@jwt_required(optional=True)
def logout():
    """
    Logout user - clear cookies and optionally revoke token.
    """
    response = make_response(jsonify(LogoutResponse().model_dump()))
    unset_jwt_cookies(response)

    # Optionally revoke token (add to blacklist)
    jwt = get_jwt()
    if jwt:
        jti = jwt.get("jti")
        container = get_container()
        if container.token_issuer:
            container.token_issuer.revoke_token(jti)

    return response

@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    """
    Refresh access token using refresh token.
    """
    user_id = get_jwt_identity()
    container = get_container()

    # Get fresh permissions
    authz_service = container.authorization_service
    permissions = list(authz_service.get_user_permissions(user_id))

    # Create new access token
    new_access_token = container.token_issuer.create_access_token(
        user_id,
        {"permissions": permissions}
    )

    response_data = RefreshResponse(access_token=new_access_token)
    response = make_response(jsonify(response_data.model_dump()))
    set_access_cookies(response, new_access_token)

    return response

@auth_bp.route("/me", methods=["GET"])
@jwt_required()
def get_current_user():
    """
    Get current authenticated user info.
    """
    user_id = get_jwt_identity()
    jwt_claims = get_jwt()

    container = get_container()
    user = container.user_repository.find_by_id(user_id)

    if not user:
        return jsonify(ErrorResponse(
            error="NotFound",
            message="User not found",
            status_code=404
        ).model_dump()), 404

    return jsonify(UserResponse(
        id=user.id,
        email=user.email,
        permissions=jwt_claims.get("permissions", []),
        roles=[r.name for r in user.roles]
    ).model_dump())
```

### Step 4: Create Auth Middleware/Decorators

**`app/api/v1/auth/middleware.py`**
```python
from functools import wraps
from flask import jsonify
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity, get_jwt

from wiring import get_container

def require_permission(*required_permissions):
    """
    Decorator to require specific permissions.
    Usage: @require_permission("project:create", "project:update")
    """
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            verify_jwt_in_request()
            jwt_claims = get_jwt()
            user_permissions = set(jwt_claims.get("permissions", []))

            if not all(p in user_permissions for p in required_permissions):
                return jsonify({
                    "error": "Forbidden",
                    "message": f"Required permissions: {', '.join(required_permissions)}",
                    "status_code": 403
                }), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator

def require_any_permission(*required_permissions):
    """
    Decorator to require any of the specified permissions.
    Usage: @require_any_permission("project:read", "project:admin")
    """
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            verify_jwt_in_request()
            jwt_claims = get_jwt()
            user_permissions = set(jwt_claims.get("permissions", []))

            if not any(p in user_permissions for p in required_permissions):
                return jsonify({
                    "error": "Forbidden",
                    "message": f"Required one of: {', '.join(required_permissions)}",
                    "status_code": 403
                }), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator

def require_role(*required_roles):
    """
    Decorator to require specific roles.
    Usage: @require_role("admin")
    """
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            verify_jwt_in_request()
            user_id = get_jwt_identity()

            container = get_container()
            authz = container.authorization_service

            if not any(authz.has_role(user_id, role) for role in required_roles):
                return jsonify({
                    "error": "Forbidden",
                    "message": f"Required role: {', '.join(required_roles)}",
                    "status_code": 403
                }), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator
```

### Step 5: Initialize JWT Extension

**Update `app/__init__.py`**
```python
from flask_jwt_extended import JWTManager

jwt = JWTManager()

def create_app(config_class: type = Config) -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_class)

    # Initialize extensions
    CORS(app)
    jwt.init_app(app)

    # JWT error handlers
    @jwt.expired_token_loader
    def expired_token_callback(jwt_header, jwt_payload):
        return jsonify({
            "error": "TokenExpired",
            "message": "Token has expired",
            "status_code": 401
        }), 401

    @jwt.invalid_token_loader
    def invalid_token_callback(error):
        return jsonify({
            "error": "InvalidToken",
            "message": "Token is invalid",
            "status_code": 401
        }), 401

    @jwt.unauthorized_loader
    def missing_token_callback(error):
        return jsonify({
            "error": "Unauthorized",
            "message": "Missing authentication token",
            "status_code": 401
        }), 401

    # Register blueprints
    from app.api.v1 import bp as api_v1_bp
    from app.api.v1.auth import auth_bp
    app.register_blueprint(api_v1_bp, url_prefix="/api/v1")

    return app
```

### Step 6: Add Rate Limiting

**`app/infrastructure/rate_limiter.py`**
```python
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["100 per minute"]
)

# Apply to login route in routes.py:
# @limiter.limit("5 per minute")
# def login(): ...
```

## Todo List

- [x] Update config with JWT settings
- [x] Create Pydantic request/response schemas
- [x] Create auth blueprint
- [x] Implement login endpoint
- [x] Implement logout endpoint
- [x] Implement refresh endpoint
- [x] Implement /me endpoint
- [x] Create permission/role decorators
- [x] Initialize JWT extension with error handlers
- [x] Add rate limiting on login
- [x] Test all endpoints manually
- [x] Add integration tests
- [ ] Replace in-memory blacklist with Redis (action item from validation)

## Success Criteria

- [x] Login returns tokens with valid credentials
- [x] Login returns 401 with invalid credentials
- [x] Logout clears cookies and revokes token
- [x] Refresh returns new access token
- [x] /me returns user info when authenticated
- [x] Permission decorator blocks unauthorized access
- [x] Rate limiting triggers after 5 failed logins

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| CORS issues | Medium | Medium | Test with actual frontend |
| Cookie not set | Medium | Medium | Check SameSite/Secure flags |
| Rate limit too strict | Low | Low | Make configurable |

## Security Considerations

- Never return password hash in response
- Generic error for invalid credentials (prevent enumeration)
- Rate limit login to prevent brute force
- CSRF protection via double-submit cookie
- Secure cookie flags in production

## Next Steps

After this phase:
→ [Phase 04: Frontend Auth Infrastructure](phase-04-frontend-auth-infra.md)
