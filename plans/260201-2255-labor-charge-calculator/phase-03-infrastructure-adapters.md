# Phase 03: Infrastructure Adapters

## Context Links

- [Parent Plan](./plan.md)
- [Phase 01](./phase-01-database-and-domain-layer.md) (entities), [Phase 02](./phase-02-application-layer-use-cases.md) (ports)
- Reference: `app/infrastructure/adapters/sqlalchemy_project.py`
- Reference: `app/infrastructure/database/models/project.py`

## Overview

- **Date:** 2026-02-01
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Create SQLAlchemy ORM models, repository adapter implementations, wire into DI container, and seed the `project:manage_labor` permission.

## Key Insights

- ORM models in `app/infrastructure/database/models/` extend `Base`
- Adapters in `app/infrastructure/adapters/` named `SQLAlchemy{Entity}Repository`
- Each adapter takes `session: Session`, has `_to_entity()` mapper
- DI wiring: add repos + use cases to Container dataclass in `wiring.py`
- Seed: add to `DEFAULT_PERMISSIONS` list and manager role in `scripts/seed_auth.py`

## Requirements

**Functional:**
- WorkerModel: maps to `workers` table
- LaborEntryModel: maps to `labor_entries` table
- SQLAlchemyWorkerRepository implements IWorkerRepository
- SQLAlchemyLaborEntryRepository implements ILaborEntryRepository
- Container updated with labor repositories and all 9 use cases
- `project:manage_labor` permission seeded and added to manager role

**Non-functional:**
- Use `joinedload` for relationships where appropriate
- Catch `IntegrityError` for duplicate entry detection
- Each file under 200 lines

## Architecture

```
infrastructure/
  database/models/
    worker.py          -- WorkerModel
    labor_entry.py     -- LaborEntryModel
  adapters/
    sqlalchemy_worker.py       -- SQLAlchemyWorkerRepository
    sqlalchemy_labor_entry.py  -- SQLAlchemyLaborEntryRepository
```

## Related Code Files

**Create:**
- `construction-back-end/app/infrastructure/database/models/worker.py`
- `construction-back-end/app/infrastructure/database/models/labor_entry.py`
- `construction-back-end/app/infrastructure/adapters/sqlalchemy_worker.py`
- `construction-back-end/app/infrastructure/adapters/sqlalchemy_labor_entry.py`

**Modify:**
- `construction-back-end/app/infrastructure/database/models/__init__.py` -- export WorkerModel, LaborEntryModel
- `construction-back-end/wiring.py` -- add labor repos + use cases to Container
- `construction-back-end/app/__init__.py` -- add labor repos to `_configure_di_container()`
- `construction-back-end/scripts/seed_auth.py` -- add `project:manage_labor` permission + assign to manager role

## Implementation Steps

1. **Create `models/worker.py`:**
   ```python
   class WorkerModel(Base):
       __tablename__ = "workers"
       id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
       project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id"), nullable=False, index=True)
       name = Column(String(255), nullable=False)
       phone = Column(String(50), nullable=True)
       daily_rate = Column(Numeric(10, 2), nullable=False)
       is_active = Column(Boolean, default=True, nullable=False)
       created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
       updated_at = Column(DateTime, default=..., onupdate=...)
       # Relationships
       project = relationship("ProjectModel")
       labor_entries = relationship("LaborEntryModel", back_populates="worker")
   ```

2. **Create `models/labor_entry.py`:**
   ```python
   class LaborEntryModel(Base):
       __tablename__ = "labor_entries"
       id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
       worker_id = Column(UUID(as_uuid=True), ForeignKey("workers.id"), nullable=False, index=True)
       date = Column(Date, nullable=False)
       amount_override = Column(Numeric(10, 2), nullable=True)
       note = Column(String(500), nullable=True)
       created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
       __table_args__ = (UniqueConstraint("worker_id", "date", name="uq_worker_date"),)
       # Relationships
       worker = relationship("WorkerModel", back_populates="labor_entries")
   ```

3. **Update `models/__init__.py`:**
   Add imports for `WorkerModel` and `LaborEntryModel` to `__all__`

4. **Create `adapters/sqlalchemy_worker.py`:**
   - `__init__(self, session: Session)`
   - `create()`: create WorkerModel, flush, return entity
   - `find_by_id()`: query by id, return entity or None
   - `list_by_project()`: filter by project_id + optionally is_active=True
   - `update()`: find model, update fields, flush
   - `soft_delete()`: set is_active=False, flush
   - `_to_entity()`: map WorkerModel -> Worker domain entity

5. **Create `adapters/sqlalchemy_labor_entry.py`:**
   - `create()`: try insert, catch `IntegrityError` -> raise `DuplicateEntryError`
   - `find_by_id()`: query by id
   - `list_by_project()`: join with workers, filter by project_id + optional date_from/date_to/worker_id
   - `update()`: find, update fields, flush
   - `delete()`: delete entry
   - `get_summary()`: SQL aggregation query -- GROUP BY worker, SUM effective cost using COALESCE
   - `_to_entity()`: map LaborEntryModel -> LaborEntry domain entity

6. **Update `wiring.py`:**
   - Import labor ports and use cases
   - Add to Container: `worker_repository`, `labor_entry_repository`, plus 9 use case fields
   - In `configure_container()`: accept `worker_repository`, `labor_entry_repository` params
   - Conditional wiring: if both repos provided, wire all use cases

7. **Update `app/__init__.py` (`_configure_di_container()`):**
   - Import `SQLAlchemyWorkerRepository`, `SQLAlchemyLaborEntryRepository`
   - Pass both to `configure_container()` call

8. **Update `scripts/seed_auth.py`:**
   - Add `{"name": "project:manage_labor", "resource": "project", "action": "manage_labor"}` to `DEFAULT_PERMISSIONS`
   - Add `"project:manage_labor"` to manager role's permissions list

## Todo List

- [ ] Create WorkerModel
- [ ] Create LaborEntryModel
- [ ] Update models __init__.py
- [ ] Create SQLAlchemyWorkerRepository
- [ ] Create SQLAlchemyLaborEntryRepository
- [ ] Update wiring.py Container + configure_container
- [ ] Update app/__init__.py DI configuration
- [ ] Update seed_auth.py with manage_labor permission
- [ ] Run seed script to verify permission added

## Success Criteria

- Models importable from `app.infrastructure.database.models`
- Repositories pass interface contracts
- DI container wires correctly at startup
- `project:manage_labor` permission exists in DB after seed

## Risk Assessment

- **IntegrityError handling:** Must import from `sqlalchemy.exc`, catch specifically for unique constraint
- **Session management:** Use `flush()` not `commit()` inside repos (Flask-SQLAlchemy manages commits)
- **Circular imports:** Models __init__ imports must not trigger circular chain

## Security Considerations

- RBAC: `project:manage_labor` grants write access to labor data; read uses `project:read`
- Admins (`*:*`) automatically have all permissions via wildcard check

## Next Steps

- Phase 04: API endpoints consume these adapters via DI container
