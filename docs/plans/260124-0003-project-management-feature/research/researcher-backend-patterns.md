# Flask Hexagonal Architecture Patterns for CRUD Operations

**Date:** 2026-01-24
**Focus:** SQLAlchemy many-to-many, Repository pattern, Use case, RBAC enforcement

## Executive Summary

Flask hexagonal architecture works best for complex business logic with testability requirements. For straightforward CRUD, the pattern prevents over-engineering. Your project applies it selectively: thin controllers + rich use cases + repository layer. SQLAlchemy 2.0 association tables handle many-to-many efficiently.

---

## 1. SQLAlchemy Many-to-Many Relationship Pattern

**Current Implementation (exists):**
```python
# app/infrastructure/database/models.py

user_projects = Table(
    "user_projects",
    Base.metadata,
    Column("user_id", UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True),
    Column("project_id", UUID(as_uuid=True), ForeignKey("projects.id"), primary_key=True),
    Column("assigned_at", DateTime, default=lambda: datetime.now(timezone.utc)),
    # Optional: role, permissions_override columns for association object pattern
)

class ProjectModel(Base):
    __tablename__ = "projects"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    # Many-to-many: projects have many users
    users = relationship("UserModel", secondary=user_projects, back_populates="projects")
    owner = relationship("UserModel")
```

**Key Benefits:**
- Clean separation: junction table handles FK constraints
- `assigned_at` timestamp captures audit data
- `joinedload()` prevents N+1 query problems
- Supports future columns without refactoring (association object pattern)

---

## 2. Repository Pattern Implementation

**Port (Interface):**
```python
# app/application/projects/ports.py

from abc import ABC, abstractmethod
from typing import Optional, List
from uuid import UUID

class IProjectRepository(ABC):
    @abstractmethod
    def create(self, project_id: UUID, name: str, owner_id: UUID) -> None:
        ...

    @abstractmethod
    def find_by_id(self, project_id: UUID) -> Optional[dict]:
        ...

    @abstractmethod
    def list_by_owner(self, owner_id: UUID) -> List[dict]:
        ...

    @abstractmethod
    def add_user(self, project_id: UUID, user_id: UUID) -> None:
        ...

    @abstractmethod
    def remove_user(self, project_id: UUID, user_id: UUID) -> None:
        ...
```

**Adapter (SQLAlchemy Implementation):**
```python
# app/infrastructure/database/repositories/project_repository.py

from sqlalchemy.orm import Session, joinedload
from app.application.projects.ports import IProjectRepository

class SqlAlchemyProjectRepository(IProjectRepository):
    def __init__(self, session: Session):
        self._session = session

    def create(self, project_id: UUID, name: str, owner_id: UUID) -> None:
        project = ProjectModel(
            id=project_id,
            name=name,
            owner_id=owner_id
        )
        self._session.add(project)
        self._session.flush()  # Get ID without commit

    def find_by_id(self, project_id: UUID) -> Optional[dict]:
        project = self._session.query(ProjectModel)\
            .options(joinedload(ProjectModel.users))\
            .filter_by(id=project_id).first()

        return {
            "id": str(project.id),
            "name": project.name,
            "owner_id": str(project.owner_id),
            "users": [str(u.id) for u in project.users],
            "created_at": project.created_at.isoformat()
        } if project else None

    def list_by_owner(self, owner_id: UUID) -> List[dict]:
        projects = self._session.query(ProjectModel)\
            .filter_by(owner_id=owner_id).all()

        return [{
            "id": str(p.id),
            "name": p.name,
            "owner_id": str(p.owner_id),
            "user_count": len(p.users)
        } for p in projects]

    def add_user(self, project_id: UUID, user_id: UUID) -> None:
        project = self._session.query(ProjectModel).get(project_id)
        user = self._session.query(UserModel).get(user_id)
        if project and user:
            project.users.append(user)

    def remove_user(self, project_id: UUID, user_id: UUID) -> None:
        project = self._session.query(ProjectModel).get(project_id)
        user = self._session.query(UserModel).get(user_id)
        if project and user:
            project.users.remove(user)
```

---

## 3. Use Case Pattern for CRUD

**Principle:** Single responsibility, explicit input/output, no framework dependencies

```python
# app/application/projects/create_project_usecase.py

from dataclasses import dataclass
from uuid import UUID, uuid4
from app.application.projects.ports import IProjectRepository
from app.domain.exceptions import PermissionDeniedError, InvalidInputError

@dataclass
class CreateProjectRequest:
    name: str
    description: str
    owner_id: UUID

@dataclass
class CreateProjectResponse:
    project_id: str
    name: str
    created_at: str

class CreateProjectUseCase:
    def __init__(self, project_repo: IProjectRepository):
        self._repo = project_repo

    def execute(self, request: CreateProjectRequest) -> CreateProjectResponse:
        # Domain validation
        if not request.name or len(request.name.strip()) == 0:
            raise InvalidInputError("Project name required")

        if len(request.name) > 255:
            raise InvalidInputError("Project name too long")

        # Business logic: only active users can create projects (future: check via user repo)

        project_id = uuid4()
        self._repo.create(project_id, request.name.strip(), request.owner_id)

        return CreateProjectResponse(
            project_id=str(project_id),
            name=request.name,
            created_at=datetime.now(timezone.utc).isoformat()
        )
```

---

## 4. API Route with Permission Checking

**Pydantic Schema:**
```python
# app/api/v1/projects/schemas.py

from pydantic import BaseModel, Field
from typing import Optional

class CreateProjectRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None

class ProjectResponse(BaseModel):
    id: str
    name: str
    owner_id: str
    user_count: int
    created_at: str
```

**Route with RBAC:**
```python
# app/api/v1/projects/routes.py

from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.infrastructure.authorization.rbac_service import RBACService
from app.application.projects.create_project_usecase import CreateProjectUseCase
from app.application.projects.ports import IProjectRepository

projects_bp = Blueprint("projects", __name__, url_prefix="/api/v1/projects")

def require_permission(permission: str):
    """Decorator: check permission before proceeding"""
    def decorator(fn):
        def wrapper(*args, **kwargs):
            user_id = get_jwt_identity()
            rbac = get_container().rbac_service

            if not rbac.has_permission(user_id, permission):
                return jsonify({"error": "Forbidden", "message": f"Missing: {permission}"}), 403

            return fn(*args, **kwargs)
        return wrapper
    return decorator

@projects_bp.route("", methods=["POST"])
@jwt_required()
@require_permission("project:create")
def create_project():
    """Create a new project"""
    try:
        data = CreateProjectRequest(**request.get_json())
    except ValidationError as e:
        return jsonify({"error": "Validation error", "details": e.errors()}), 400

    container = get_container()
    user_id = get_jwt_identity()

    request_dto = CreateProjectRequest(
        name=data.name,
        description=data.description,
        owner_id=UUID(user_id)
    )

    response = container.create_project_usecase.execute(request_dto)
    return jsonify(response.model_dump()), 201

@projects_bp.route("/<project_id>/users/<user_id>", methods=["POST"])
@jwt_required()
@require_permission("project:manage_users")
def add_user_to_project(project_id: str, user_id: str):
    """Add user to project (requires project:manage_users permission)"""
    container = get_container()
    repo = container.project_repository

    try:
        repo.add_user(UUID(project_id), UUID(user_id))
        return jsonify({"message": "User added"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 400
```

---

## 5. Key Patterns Summary

| Pattern | Purpose | Implementation |
|---------|---------|-----------------|
| **Port** | Define contract for persistence | ABC interface |
| **Adapter** | SQLAlchemy concrete impl | Repository class |
| **Use Case** | Business workflow orchestration | Single execute() method |
| **Schema** | Request/response validation | Pydantic models |
| **RBAC** | Permission enforcement | Decorator on routes |

---

## 6. Critical Design Decisions for Your Project

1. **Many-to-Many with Timestamps:** Your `user_projects` table has `assigned_at` → use association table (not association object) unless you need per-membership metadata.

2. **N+1 Prevention:** Always use `joinedload()` when fetching related users/projects.

3. **Permission Checks:** Do NOT rely on JWT claims alone—verify permissions in backend before data modification.

4. **Dependency Injection:** Container injects repository into use case; use case is used by route.

5. **DTOs vs. Models:** Repository returns dicts/DTOs, not ORM models. Prevents ORM leakage into application layer.

---

## Sources & References

- [SQLAlchemy 2.0 Many-to-Many](https://docs.sqlalchemy.org/en/20/orm/basic_relationships.html)
- [Hexagonal Architecture in Python](https://alexgrover.me/writing/python-hexagonal-architecture)
- [Flask RBAC Implementation](https://www.geeksforgeeks.org/python/flask-role-based-access-control/)
- [Pydantic with Flask](https://hrekov.com/blog/flask-request-response-pydantic-serialisation)
- [Code Standards (project)](/Users/sweet-home/Works/construction/docs/code-standards-backend.md)

---

## Unresolved Questions

- Should `user_projects` junction table have additional columns (role override, access level)? Defer until feature requires it (YAGNI).
- How to handle permission caching for high-load scenarios? Redis strategy needed if >10k users.
- Async repository support (SQLAlchemy 2.0 async) or stick to sync? Deferred until bottleneck proven.
