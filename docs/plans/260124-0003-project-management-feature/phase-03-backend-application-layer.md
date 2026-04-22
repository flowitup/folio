# Phase 03: Backend Application Layer

## Context Links

- [Backend Patterns Research](./research/researcher-backend-patterns.md)
- [Existing LoginUseCase](../../construction-back-end/app/application/usecases/login_usecase.py)
- [Existing UserRepositoryPort](../../construction-back-end/app/application/ports/user_repository_port.py)
- [Wiring Container](../../construction-back-end/wiring.py)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 1h |

Create use cases and repository port for project CRUD operations following hexagonal architecture.

## Key Insights

- Use cases have single `execute()` method
- Repository port is Protocol (interface)
- Input/output via dataclasses (DTOs)
- Use cases injected with repository via constructor

## Requirements

### Functional
- CreateProjectUseCase: Create new project with owner
- UpdateProjectUseCase: Update name/address
- DeleteProjectUseCase: Remove project
- ListProjectsUseCase: List projects for user (assigned or all for admin)
- GetProjectUseCase: Get single project by ID

### Non-Functional
- All use cases testable without database
- DTOs prevent ORM leakage
- Type hints on all public methods

## Architecture

```
application/
├── projects/
│   ├── __init__.py
│   ├── ports.py                    # IProjectRepository
│   ├── create_project_usecase.py
│   ├── update_project_usecase.py
│   ├── delete_project_usecase.py
│   ├── list_projects_usecase.py
│   └── get_project_usecase.py
```

## Related Code Files

### Create
- `construction-back-end/app/application/projects/__init__.py`
- `construction-back-end/app/application/projects/ports.py`
- `construction-back-end/app/application/projects/create_project_usecase.py`
- `construction-back-end/app/application/projects/update_project_usecase.py`
- `construction-back-end/app/application/projects/delete_project_usecase.py`
- `construction-back-end/app/application/projects/list_projects_usecase.py`
- `construction-back-end/app/application/projects/get_project_usecase.py`
- `construction-back-end/app/infrastructure/adapters/sqlalchemy_project_repository.py`

### Modify
- `construction-back-end/wiring.py` (add project repository + use cases)

## Implementation Steps

### 1. Create Repository Port

File: `app/application/projects/ports.py`
```python
"""Project repository port."""

from abc import ABC, abstractmethod
from typing import Optional, List
from uuid import UUID

from app.domain.entities.project import Project


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
    def list_all(self) -> List[Project]:
        """List all projects (admin only)."""
        ...

    @abstractmethod
    def update(self, project: Project) -> Project:
        """Update existing project."""
        ...

    @abstractmethod
    def delete(self, project_id: UUID) -> bool:
        """Delete project. Returns True if deleted."""
        ...

    @abstractmethod
    def add_user(self, project_id: UUID, user_id: UUID) -> None:
        """Assign user to project."""
        ...

    @abstractmethod
    def remove_user(self, project_id: UUID, user_id: UUID) -> None:
        """Remove user from project."""
        ...
```

### 2. Create Use Cases

**CreateProjectUseCase** (`create_project_usecase.py`):
```python
"""Create project use case."""

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID, uuid4

from app.application.projects.ports import IProjectRepository
from app.domain.entities.project import Project
from app.domain.exceptions.project_exceptions import InvalidProjectDataError


@dataclass
class CreateProjectRequest:
    name: str
    address: Optional[str]
    owner_id: UUID


@dataclass
class CreateProjectResponse:
    id: str
    name: str
    address: Optional[str]
    owner_id: str
    created_at: str


class CreateProjectUseCase:
    """Create a new construction project."""

    def __init__(self, project_repo: IProjectRepository):
        self._repo = project_repo

    def execute(self, request: CreateProjectRequest) -> CreateProjectResponse:
        # Validation
        if not request.name or len(request.name.strip()) == 0:
            raise InvalidProjectDataError("Project name is required")
        if len(request.name) > 255:
            raise InvalidProjectDataError("Project name exceeds 255 characters")

        project = Project(
            id=uuid4(),
            name=request.name.strip(),
            address=request.address.strip() if request.address else None,
            owner_id=request.owner_id,
            created_at=datetime.now(timezone.utc),
        )

        saved = self._repo.create(project)

        return CreateProjectResponse(
            id=str(saved.id),
            name=saved.name,
            address=saved.address,
            owner_id=str(saved.owner_id),
            created_at=saved.created_at.isoformat(),
        )
```

**ListProjectsUseCase** (`list_projects_usecase.py`):
```python
"""List projects use case."""

from dataclasses import dataclass
from typing import List
from uuid import UUID

from app.application.projects.ports import IProjectRepository


@dataclass
class ProjectSummary:
    id: str
    name: str
    address: str | None
    owner_id: str
    user_count: int


class ListProjectsUseCase:
    """List projects for a user or all (admin)."""

    def __init__(self, project_repo: IProjectRepository):
        self._repo = project_repo

    def execute(self, user_id: UUID, is_admin: bool = False) -> List[ProjectSummary]:
        if is_admin:
            projects = self._repo.list_all()
        else:
            projects = self._repo.list_by_user(user_id)

        return [
            ProjectSummary(
                id=str(p.id),
                name=p.name,
                address=p.address,
                owner_id=str(p.owner_id),
                user_count=len(p.user_ids) if p.user_ids else 0,
            )
            for p in projects
        ]
```

### 3. Create SQLAlchemy Repository Adapter

File: `app/infrastructure/adapters/sqlalchemy_project_repository.py`
```python
"""SQLAlchemy implementation of project repository."""

from typing import Optional, List
from uuid import UUID

from sqlalchemy.orm import Session, joinedload

from app.application.projects.ports import IProjectRepository
from app.domain.entities.project import Project
from app.infrastructure.database.models import ProjectModel, UserModel, user_projects


class SqlAlchemyProjectRepository(IProjectRepository):
    """SQLAlchemy adapter for project persistence."""

    def __init__(self, session: Session):
        self._session = session

    def create(self, project: Project) -> Project:
        model = ProjectModel(
            id=project.id,
            name=project.name,
            address=project.address,
            owner_id=project.owner_id,
            created_at=project.created_at,
        )
        self._session.add(model)
        self._session.flush()
        return self._to_entity(model)

    def find_by_id(self, project_id: UUID) -> Optional[Project]:
        model = (
            self._session.query(ProjectModel)
            .options(joinedload(ProjectModel.users))
            .filter_by(id=project_id)
            .first()
        )
        return self._to_entity(model) if model else None

    def list_by_user(self, user_id: UUID) -> List[Project]:
        models = (
            self._session.query(ProjectModel)
            .join(user_projects)
            .filter(user_projects.c.user_id == user_id)
            .options(joinedload(ProjectModel.users))
            .all()
        )
        return [self._to_entity(m) for m in models]

    def list_all(self) -> List[Project]:
        models = (
            self._session.query(ProjectModel)
            .options(joinedload(ProjectModel.users))
            .all()
        )
        return [self._to_entity(m) for m in models]

    def update(self, project: Project) -> Project:
        model = self._session.query(ProjectModel).filter_by(id=project.id).first()
        if model:
            model.name = project.name
            model.address = project.address
            self._session.flush()
            return self._to_entity(model)
        return project

    def delete(self, project_id: UUID) -> bool:
        result = self._session.query(ProjectModel).filter_by(id=project_id).delete()
        return result > 0

    def add_user(self, project_id: UUID, user_id: UUID) -> None:
        project = self._session.query(ProjectModel).get(project_id)
        user = self._session.query(UserModel).get(user_id)
        if project and user and user not in project.users:
            project.users.append(user)

    def remove_user(self, project_id: UUID, user_id: UUID) -> None:
        project = self._session.query(ProjectModel).get(project_id)
        user = self._session.query(UserModel).get(user_id)
        if project and user and user in project.users:
            project.users.remove(user)

    def _to_entity(self, model: ProjectModel) -> Project:
        return Project(
            id=model.id,
            name=model.name,
            address=model.address,
            owner_id=model.owner_id,
            created_at=model.created_at,
            user_ids=[u.id for u in model.users] if model.users else [],
        )
```

### 4. Update Wiring Container

Add to `wiring.py`:
```python
# Import new use cases
from app.application.projects.create_project_usecase import CreateProjectUseCase
from app.application.projects.list_projects_usecase import ListProjectsUseCase
# ... other use cases

# In Container dataclass:
project_repository: Optional[IProjectRepository] = None
create_project_usecase: Optional[CreateProjectUseCase] = None
list_projects_usecase: Optional[ListProjectsUseCase] = None
# ... other use cases

# In configure_container():
if project_repository:
    container.create_project_usecase = CreateProjectUseCase(project_repository)
    container.list_projects_usecase = ListProjectsUseCase(project_repository)
```

## Todo List

- [ ] Create `app/application/projects/` directory
- [ ] Create `ports.py` with IProjectRepository
- [ ] Create `create_project_usecase.py`
- [ ] Create `update_project_usecase.py`
- [ ] Create `delete_project_usecase.py`
- [ ] Create `list_projects_usecase.py`
- [ ] Create `get_project_usecase.py`
- [ ] Create `sqlalchemy_project_repository.py` adapter
- [ ] Update `wiring.py` with new dependencies
- [ ] Update `__init__.py` exports

## Success Criteria

1. All use cases importable and instantiable
2. Repository port defines complete interface
3. SQLAlchemy adapter implements all port methods
4. Container wires dependencies correctly
5. Use cases testable with mock repository

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Session scope issues | Medium | Use request-scoped session |
| N+1 queries | Medium | Use joinedload consistently |
| Missing flush/commit | Medium | Test transaction behavior |

## Security Considerations

- Use cases don't check permissions (done at API layer)
- Repository returns only requested data
- No SQL injection risk with ORM

## Next Steps

After completion:
1. Proceed to Phase 04 (API endpoints)
2. Write unit tests for use cases with mock repo
