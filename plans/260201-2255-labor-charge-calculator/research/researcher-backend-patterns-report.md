# Backend Patterns Research Report

**Date:** 2026-02-01
**Source:** /Users/sweet-home/Works/construction/construction-back-end/

## 1. Domain Entity Pattern

**File:** `app/domain/entities/project.py`

```python
from dataclasses import dataclass, field
from uuid import UUID

@dataclass(slots=True)
class Project:
    """Project aggregate root."""
    id: UUID
    name: str
    owner_id: UUID
    created_at: datetime
    address: Optional[str] = None
    updated_at: Optional[datetime] = None
    user_ids: List[UUID] = field(default_factory=list)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Project):
            return NotImplemented
        return self.id == other.id

    def __hash__(self) -> int:
        return hash(self.id)
```

**Pattern:**
- Use `@dataclass(slots=True)` for memory efficiency
- Required fields first, optional fields with defaults after
- UUID for all IDs (never strings)
- Implement `__eq__` (compare by id only) and `__hash__` for collections
- Factory pattern: no `__init__` parameters, uses dataclass defaults
- List fields use `field(default_factory=list)` to avoid mutable default issues

---

## 2. Application Use Case Pattern

**File:** `app/application/projects/ports.py`

```python
from abc import ABC, abstractmethod
from uuid import UUID

class IProjectRepository(ABC):
    """Port for project persistence operations."""

    @abstractmethod
    def create(self, project: Project) -> Project:
        """Create a new project. Returns created project."""
        ...

    @abstractmethod
    def find_by_id(self, project_id: UUID) -> Optional[Project]:
        """Find project by ID. Returns None if not found."""
        ...

    @abstractmethod
    def list_by_user(self, user_id: UUID) -> List[Project]:
        """List projects user is assigned to."""
        ...

    @abstractmethod
    def update(self, project: Project) -> Project:
        """Update existing project."""
        ...
```

**Pattern:**
- Port class named `I{Entity}Repository(ABC)` in `app/application/{entity}/ports.py`
- All methods fully documented with docstrings
- Return types explicit (None if not found, not exceptions)
- Accept domain entities, return domain entities (no DTOs in ports)

**Use Case Example Pattern** (from routes):
```python
# Injected from container
result = container.create_project_usecase.execute(CreateDTO(
    name=data.name,
    address=data.address,
    owner_id=UUID(user_id)
))
```

---

## 3. Infrastructure Adapter Pattern

**File:** `app/infrastructure/adapters/sqlalchemy_project.py`

```python
from sqlalchemy.orm import Session, joinedload

class SQLAlchemyProjectRepository(IProjectRepository):
    """SQLAlchemy adapter for project persistence."""

    def __init__(self, session: Session):
        self._session = session

    def find_by_id(self, project_id: UUID) -> Optional[Project]:
        model = (
            self._session.query(ProjectModel)
            .options(joinedload(ProjectModel.users))
            .filter_by(id=project_id)
            .first()
        )
        return self._to_entity(model) if model else None

    def _to_entity(self, model: ProjectModel) -> Project:
        """Map ORM model to domain entity."""
        return Project(
            id=model.id,
            name=model.name,
            owner_id=model.owner_id,
            created_at=model.created_at,
            updated_at=model.updated_at,
            user_ids=[u.id for u in model.users] if model.users else [],
        )
```

**Pattern:**
- Adapter class named `SQLAlchemy{Entity}Repository(I{Entity}Repository)`
- Constructor takes `session: Session` only
- Private method `_to_entity()` converts ORM model → domain entity
- Use `joinedload()` for eager loading relationships
- Always check `if model` before accessing attributes

---

## 4. API Route + Schema Pattern

**File:** `app/api/v1/projects/routes.py` & `schemas.py`

```python
# Schemas (Pydantic)
from pydantic import BaseModel, Field

class CreateProjectRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    address: Optional[str] = Field(None, max_length=500)

class ProjectResponse(BaseModel):
    id: str
    name: str
    owner_id: str
    created_at: str
```

**Routes Pattern:**
```python
from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt_identity
from app.api.v1.projects.decorators import require_permission

@projects_bp.route("", methods=["POST"])
@jwt_required()
@limiter.limit("10 per minute")
@require_permission("project:create")
def create_project():
    """Create a new project."""
    try:
        data = CreateProjectRequest(**request.get_json())
    except ValidationError as e:
        error_fields = [err.get("loc", ["unknown"])[-1] for err in e.errors()]
        return jsonify(ErrorResponse(
            error="ValidationError",
            message=f"Invalid input: {', '.join(str(f) for f in error_fields)}",
            status_code=400
        ).model_dump()), 400

    container = get_container()
    user_id = get_jwt_identity()

    try:
        result = container.create_project_usecase.execute(CreateDTO(...))
    except InvalidProjectDataError as e:
        return jsonify(ErrorResponse(...).model_dump()), 400

    return jsonify(ProjectResponse(...).model_dump()), 201
```

**Pattern:**
- Decorators: `@jwt_required()` → `@limiter.limit()` → `@require_permission()`
- Validation: catch `ValidationError` from Pydantic, extract field names
- Container injection: `container = get_container()` per route
- User extraction: `user_id = get_jwt_identity()`
- Exception handling: catch domain exceptions, return standardized error responses
- Response: `jsonify(schema.model_dump()), status_code`

---

## 5. DI Wiring Pattern

**File:** `wiring.py`

```python
from dataclasses import dataclass

@dataclass
class Container:
    """Dependency Injection Container."""
    # Infrastructure
    project_repository: Optional[IProjectRepository] = None
    user_repository: Optional[UserRepositoryPort] = None

    # Use cases
    create_project_usecase: Optional[CreateProjectUseCase] = None
    list_projects_usecase: Optional[ListProjectsUseCase] = None

def configure_container(
    project_repository: Optional[IProjectRepository] = None,
    user_repository: Optional[UserRepositoryPort] = None,
) -> Container:
    """Configure DI container at startup."""
    global container
    container = Container(
        project_repository=project_repository,
        user_repository=user_repository,
    )

    # Wire use cases only if dependencies are available
    if project_repository:
        container.create_project_usecase = CreateProjectUseCase(project_repository)
        container.list_projects_usecase = ListProjectsUseCase(project_repository)

    return container

def get_container() -> Container:
    """Get current container instance."""
    return container
```

**Pattern:**
- Single global `Container` dataclass
- Called `configure_container()` once at startup
- Conditional wiring: only create use cases if ports are injected
- Access via `get_container()` function in routes
- No service locator anti-pattern (explicit dependencies in signatures)

---

## Key Takeaways for Labor Charge Feature

1. **Entities:** Use `@dataclass(slots=True)`, UUID ids, required → optional ordering
2. **Ports:** ABC with abstract methods, return entities not DTOs, document with docstrings
3. **Adapters:** Named `SQLAlchemy{Entity}Repository`, implement `_to_entity()` mapper
4. **Routes:** Stack decorators, validate with Pydantic, catch domain exceptions
5. **DI:** Single Container, conditional wiring, access via `get_container()`

---

## Unresolved Questions

- How are relationships with labor types defined (one-to-many)?
- Should labor charge have its own aggregate root or be a value object within Project?
- Any audit trail requirements for labor charge history?
