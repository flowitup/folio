# Phase 04: Backend API Endpoints

## Context Links

- [Backend Patterns Research](./research/researcher-backend-patterns.md)
- [Existing Auth Routes](../../construction-back-end/app/api/v1/auth/routes.py)
- [Existing Auth Schemas](../../construction-back-end/app/api/v1/auth/schemas.py)
- [Rate Limiter](../../construction-back-end/app/infrastructure/rate_limiter.py)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 1.5h |

Create REST API endpoints for project CRUD with RBAC permission checking.

## Key Insights

- Follow existing auth routes pattern
- Use `@jwt_required()` for authentication
- Create `@require_permission()` decorator for RBAC
- Pydantic schemas for request/response validation
- Register blueprint in app factory

## Requirements

### Functional

| Endpoint | Method | Permission | Description |
|----------|--------|------------|-------------|
| `/api/v1/projects` | GET | `project:read` | List projects for user |
| `/api/v1/projects` | POST | `project:create` | Create new project |
| `/api/v1/projects/{id}` | GET | `project:read` | Get single project |
| `/api/v1/projects/{id}` | PUT | `project:update` | Update project |
| `/api/v1/projects/{id}` | DELETE | `project:delete` | Delete project |
| `/api/v1/projects/{id}/users` | POST | `project:manage_users` | Add user to project |
| `/api/v1/projects/{id}/users/{uid}` | DELETE | `project:manage_users` | Remove user |

### Non-Functional
- Rate limiting on write operations
- Proper HTTP status codes
- Consistent error response format
- OpenAPI documentation

## Architecture

```
api/
└── v1/
    └── projects/
        ├── __init__.py       # Blueprint registration
        ├── routes.py         # Endpoint handlers
        ├── schemas.py        # Pydantic models
        └── decorators.py     # @require_permission
```

## Related Code Files

### Create
- `construction-back-end/app/api/v1/projects/__init__.py`
- `construction-back-end/app/api/v1/projects/routes.py`
- `construction-back-end/app/api/v1/projects/schemas.py`
- `construction-back-end/app/api/v1/projects/decorators.py`

### Modify
- `construction-back-end/app/api/v1/__init__.py` (register blueprint)
- `construction-back-end/app/__init__.py` (if needed for blueprint)

### Database Seed
- Add permissions: `project:create`, `project:read`, `project:update`, `project:delete`, `project:manage_users`

## Implementation Steps

### 1. Create Pydantic Schemas

File: `app/api/v1/projects/schemas.py`
```python
"""Project API schemas."""

from pydantic import BaseModel, Field
from typing import Optional, List


class CreateProjectRequest(BaseModel):
    """Request body for creating a project."""
    name: str = Field(..., min_length=1, max_length=255)
    address: Optional[str] = Field(None, max_length=500)


class UpdateProjectRequest(BaseModel):
    """Request body for updating a project."""
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    address: Optional[str] = Field(None, max_length=500)


class AddUserRequest(BaseModel):
    """Request body for adding user to project."""
    user_id: str = Field(..., description="UUID of user to add")


class ProjectResponse(BaseModel):
    """Single project response."""
    id: str
    name: str
    address: Optional[str]
    owner_id: str
    user_count: int
    created_at: str


class ProjectListResponse(BaseModel):
    """List of projects response."""
    projects: List[ProjectResponse]
    total: int


class ErrorResponse(BaseModel):
    """Error response format."""
    error: str
    message: str
    status_code: int
```

### 2. Create Permission Decorator

File: `app/api/v1/projects/decorators.py`
```python
"""RBAC decorators for project routes."""

from functools import wraps
from flask import jsonify
from flask_jwt_extended import get_jwt_identity, get_jwt

from app.api.v1.projects.schemas import ErrorResponse


def require_permission(permission: str):
    """
    Decorator to check if current user has required permission.

    Usage:
        @require_permission("project:create")
        def create_project():
            ...
    """
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            jwt_claims = get_jwt()
            permissions = jwt_claims.get("permissions", [])

            if permission not in permissions:
                return jsonify(ErrorResponse(
                    error="Forbidden",
                    message=f"Missing permission: {permission}",
                    status_code=403
                ).model_dump()), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator


def has_permission(permission: str) -> bool:
    """Check if current user has a specific permission."""
    jwt_claims = get_jwt()
    permissions = jwt_claims.get("permissions", [])
    return permission in permissions
```

### 3. Create Routes

File: `app/api/v1/projects/routes.py`
```python
"""Project API routes."""

from uuid import UUID

from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from pydantic import ValidationError

from app.api.v1.projects import projects_bp
from app.api.v1.projects.schemas import (
    CreateProjectRequest, UpdateProjectRequest, AddUserRequest,
    ProjectResponse, ProjectListResponse, ErrorResponse
)
from app.api.v1.projects.decorators import require_permission, has_permission
from app.application.projects.create_project_usecase import CreateProjectRequest as CreateDTO
from app.domain.exceptions.project_exceptions import (
    ProjectNotFoundError, InvalidProjectDataError
)
from app.infrastructure.rate_limiter import limiter
from wiring import get_container


@projects_bp.route("", methods=["GET"])
@jwt_required()
@require_permission("project:read")
def list_projects():
    """List projects for current user (or all if admin)."""
    container = get_container()
    user_id = get_jwt_identity()
    is_admin = has_permission("project:create")  # Admins can create

    projects = container.list_projects_usecase.execute(
        UUID(user_id), is_admin=is_admin
    )

    return jsonify(ProjectListResponse(
        projects=[ProjectResponse(**p.__dict__) for p in projects],
        total=len(projects)
    ).model_dump())


@projects_bp.route("", methods=["POST"])
@jwt_required()
@limiter.limit("10 per minute")
@require_permission("project:create")
def create_project():
    """Create a new project."""
    try:
        data = CreateProjectRequest(**request.get_json())
    except ValidationError as e:
        return jsonify(ErrorResponse(
            error="ValidationError",
            message=str(e),
            status_code=400
        ).model_dump()), 400

    container = get_container()
    user_id = get_jwt_identity()

    try:
        result = container.create_project_usecase.execute(CreateDTO(
            name=data.name,
            address=data.address,
            owner_id=UUID(user_id)
        ))
    except InvalidProjectDataError as e:
        return jsonify(ErrorResponse(
            error="ValidationError",
            message=str(e),
            status_code=400
        ).model_dump()), 400

    return jsonify(ProjectResponse(
        id=result.id,
        name=result.name,
        address=result.address,
        owner_id=result.owner_id,
        user_count=0,
        created_at=result.created_at
    ).model_dump()), 201


@projects_bp.route("/<project_id>", methods=["GET"])
@jwt_required()
@require_permission("project:read")
def get_project(project_id: str):
    """Get a single project by ID."""
    container = get_container()

    try:
        project = container.get_project_usecase.execute(UUID(project_id))
    except ProjectNotFoundError:
        return jsonify(ErrorResponse(
            error="NotFound",
            message=f"Project {project_id} not found",
            status_code=404
        ).model_dump()), 404

    return jsonify(ProjectResponse(
        id=str(project.id),
        name=project.name,
        address=project.address,
        owner_id=str(project.owner_id),
        user_count=len(project.user_ids),
        created_at=project.created_at.isoformat()
    ).model_dump())


@projects_bp.route("/<project_id>", methods=["PUT"])
@jwt_required()
@limiter.limit("10 per minute")
@require_permission("project:update")
def update_project(project_id: str):
    """Update an existing project."""
    try:
        data = UpdateProjectRequest(**request.get_json())
    except ValidationError as e:
        return jsonify(ErrorResponse(
            error="ValidationError",
            message=str(e),
            status_code=400
        ).model_dump()), 400

    container = get_container()

    try:
        result = container.update_project_usecase.execute(
            UUID(project_id),
            name=data.name,
            address=data.address
        )
    except ProjectNotFoundError:
        return jsonify(ErrorResponse(
            error="NotFound",
            message=f"Project {project_id} not found",
            status_code=404
        ).model_dump()), 404

    return jsonify(ProjectResponse(
        id=str(result.id),
        name=result.name,
        address=result.address,
        owner_id=str(result.owner_id),
        user_count=len(result.user_ids),
        created_at=result.created_at.isoformat()
    ).model_dump())


@projects_bp.route("/<project_id>", methods=["DELETE"])
@jwt_required()
@limiter.limit("5 per minute")
@require_permission("project:delete")
def delete_project(project_id: str):
    """Delete a project."""
    container = get_container()

    try:
        container.delete_project_usecase.execute(UUID(project_id))
    except ProjectNotFoundError:
        return jsonify(ErrorResponse(
            error="NotFound",
            message=f"Project {project_id} not found",
            status_code=404
        ).model_dump()), 404

    return "", 204


@projects_bp.route("/<project_id>/users", methods=["POST"])
@jwt_required()
@require_permission("project:manage_users")
def add_user_to_project(project_id: str):
    """Add a user to a project."""
    try:
        data = AddUserRequest(**request.get_json())
    except ValidationError as e:
        return jsonify(ErrorResponse(
            error="ValidationError",
            message=str(e),
            status_code=400
        ).model_dump()), 400

    container = get_container()
    container.project_repository.add_user(UUID(project_id), UUID(data.user_id))

    return jsonify({"message": "User added to project"}), 200


@projects_bp.route("/<project_id>/users/<user_id>", methods=["DELETE"])
@jwt_required()
@require_permission("project:manage_users")
def remove_user_from_project(project_id: str, user_id: str):
    """Remove a user from a project."""
    container = get_container()
    container.project_repository.remove_user(UUID(project_id), UUID(user_id))

    return "", 204
```

### 4. Create Blueprint Init

File: `app/api/v1/projects/__init__.py`
```python
"""Projects API blueprint."""

from flask import Blueprint

projects_bp = Blueprint("projects", __name__, url_prefix="/api/v1/projects")

from app.api.v1.projects import routes  # noqa: E402, F401
```

### 5. Register Blueprint

In `app/api/v1/__init__.py` or `app/__init__.py`:
```python
from app.api.v1.projects import projects_bp
app.register_blueprint(projects_bp)
```

### 6. Seed Permissions

SQL to add new permissions:
```sql
INSERT INTO permissions (id, name, resource, action) VALUES
  (gen_random_uuid(), 'project:create', 'project', 'create'),
  (gen_random_uuid(), 'project:read', 'project', 'read'),
  (gen_random_uuid(), 'project:update', 'project', 'update'),
  (gen_random_uuid(), 'project:delete', 'project', 'delete'),
  (gen_random_uuid(), 'project:manage_users', 'project', 'manage_users');

-- Assign to admin role
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'admin' AND p.resource = 'project';

-- Assign read to all authenticated users
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name = 'user' AND p.name = 'project:read';
```

## Todo List

- [ ] Create `app/api/v1/projects/` directory
- [ ] Create `schemas.py` with Pydantic models
- [ ] Create `decorators.py` with `@require_permission`
- [ ] Create `routes.py` with all endpoints
- [ ] Create `__init__.py` with blueprint
- [ ] Register blueprint in app factory
- [ ] Add permissions to database seed
- [ ] Test endpoints with curl/Postman
- [ ] Update OpenAPI docs if using swagger

## Success Criteria

1. All endpoints return correct status codes
2. Unauthorized requests get 401
3. Forbidden requests get 403 with permission name
4. Validation errors get 400
5. Rate limiting works on write operations

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Permission bypass | High | Test RBAC thoroughly |
| Missing rate limit | Medium | Apply to all write ops |
| UUID validation | Low | Pydantic handles format |

## Security Considerations

- All endpoints require JWT authentication
- Write operations require admin permissions
- Rate limiting prevents abuse
- Input validation via Pydantic
- No sensitive data in error messages

## Next Steps

After completion:
1. Proceed to Phase 05 (Frontend context)
2. Integration test with frontend
