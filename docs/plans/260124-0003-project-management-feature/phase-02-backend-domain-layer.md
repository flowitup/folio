# Phase 02: Backend Domain Layer

## Context Links

- [Existing User Entity](../../construction-back-end/app/domain/entities/user.py)
- [Existing Exceptions](../../construction-back-end/app/domain/exceptions/auth_exceptions.py)
- [Code Standards](../../docs/code-standards.md)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 0.5h |

Create domain entities and exceptions for projects. Domain layer has NO framework dependencies.

## Key Insights

- Domain entities are pure Python dataclasses
- No SQLAlchemy imports in domain layer
- Exceptions carry semantic meaning for error handling
- Follow existing `User` entity pattern

## Requirements

### Functional
- `Project` entity with id, name, address, owner_id, created_at
- Domain exceptions for project-specific errors
- Value object for project name validation (optional, YAGNI)

### Non-Functional
- Zero framework dependencies
- Immutable where possible
- Type hints on all public methods

## Architecture

```
domain/
├── entities/
│   ├── project.py     # Project entity
│   └── __init__.py    # Export Project
├── exceptions/
│   ├── project_exceptions.py
│   └── __init__.py    # Export exceptions
└── value_objects/     # Optional: ProjectName VO
```

## Related Code Files

### Create
- `construction-back-end/app/domain/entities/project.py`
- `construction-back-end/app/domain/exceptions/project_exceptions.py`

### Modify
- `construction-back-end/app/domain/entities/__init__.py`
- `construction-back-end/app/domain/exceptions/__init__.py`

## Implementation Steps

1. **Create Project entity**

   File: `app/domain/entities/project.py`
   ```python
   """Project domain entity."""

   from dataclasses import dataclass
   from datetime import datetime
   from typing import Optional, List
   from uuid import UUID


   @dataclass
   class Project:
       """
       Project aggregate root.

       Represents a construction project that users can be assigned to.
       """
       id: UUID
       name: str
       address: Optional[str]
       owner_id: UUID
       created_at: datetime
       user_ids: List[UUID] = None  # Loaded when needed

       def __post_init__(self):
           if self.user_ids is None:
               self.user_ids = []
   ```

2. **Create project exceptions**

   File: `app/domain/exceptions/project_exceptions.py`
   ```python
   """Project domain exceptions."""


   class ProjectError(Exception):
       """Base exception for project domain errors."""
       pass


   class ProjectNotFoundError(ProjectError):
       """Raised when project does not exist."""
       def __init__(self, project_id: str):
           self.project_id = project_id
           super().__init__(f"Project not found: {project_id}")


   class ProjectAccessDeniedError(ProjectError):
       """Raised when user lacks permission for project operation."""
       def __init__(self, user_id: str, project_id: str, action: str):
           self.user_id = user_id
           self.project_id = project_id
           self.action = action
           super().__init__(f"User {user_id} cannot {action} project {project_id}")


   class InvalidProjectDataError(ProjectError):
       """Raised when project data validation fails."""
       def __init__(self, message: str):
           super().__init__(message)
   ```

3. **Update entities __init__.py**
   ```python
   from app.domain.entities.project import Project
   ```

4. **Update exceptions __init__.py**
   ```python
   from app.domain.exceptions.project_exceptions import (
       ProjectError,
       ProjectNotFoundError,
       ProjectAccessDeniedError,
       InvalidProjectDataError,
   )
   ```

## Todo List

- [ ] Create `project.py` entity file
- [ ] Create `project_exceptions.py` file
- [ ] Update `entities/__init__.py` exports
- [ ] Update `exceptions/__init__.py` exports
- [ ] Verify no framework imports in domain layer

## Success Criteria

1. `Project` entity importable from `app.domain.entities`
2. All exceptions importable from `app.domain.exceptions`
3. No SQLAlchemy/Flask imports in domain layer
4. Type hints present on all public members

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Circular imports | Low | Use TYPE_CHECKING |
| Over-engineering domain | Low | Keep entity simple (YAGNI) |

## Security Considerations

- No business logic in entity that could leak data
- Exceptions don't expose sensitive info in messages

## Next Steps

After completion:
1. Proceed to Phase 03 (Application layer - use cases)
2. Domain layer is testable in isolation
