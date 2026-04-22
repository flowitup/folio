# Phase 01: Database & Domain Layer

## Context Links

- [Parent Plan](./plan.md)
- [Backend Patterns Report](./research/researcher-backend-patterns-report.md)
- [Brainstorm](../reports/brainstorm-260201-2255-labor-charge-calculator.md)
- Dependencies: `projects` table must exist (migration `6689f8c8b051`)

## Overview

- **Date:** 2026-02-01
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Create Alembic migration for `workers` and `labor_entries` tables, plus domain entities and exceptions.

## Key Insights

- Follow `@dataclass(slots=True)` pattern from `app/domain/entities/project.py`
- Exceptions follow `{Feature}Error` base class pattern (see `project_exceptions.py`)
- Required fields first, optional fields with defaults after
- UUID for all IDs, `__eq__` and `__hash__` by id

## Requirements

**Functional:**
- `workers` table: id, project_id (FK projects), name, phone, daily_rate, is_active, timestamps
- `labor_entries` table: id, worker_id (FK workers), date, amount_override, note, created_at
- UNIQUE constraint on (worker_id, date)
- Domain entities: Worker, LaborEntry
- Domain exceptions: LaborError (base), WorkerNotFoundError, LaborEntryNotFoundError, DuplicateEntryError

**Non-functional:**
- DECIMAL(10,2) for EUR precision
- Index on `workers.project_id` and `labor_entries.worker_id`
- Cascade delete: labor_entries deleted when worker deleted (but workers use soft delete)

## Architecture

```
domain/
  entities/worker.py          -- Worker dataclass
  entities/labor_entry.py     -- LaborEntry dataclass
  exceptions/labor_exceptions.py -- All labor domain exceptions
migrations/
  versions/xxx_add_workers_and_labor_entries.py
```

## Related Code Files

**Create:**
- `construction-back-end/app/domain/entities/worker.py`
- `construction-back-end/app/domain/entities/labor_entry.py`
- `construction-back-end/app/domain/exceptions/labor_exceptions.py`
- `construction-back-end/migrations/versions/xxxx_add_workers_and_labor_entries.py`

**Modify:**
- `construction-back-end/app/domain/entities/__init__.py` -- export new entities
- `construction-back-end/app/domain/exceptions/__init__.py` -- export new exceptions

## Implementation Steps

1. Create `app/domain/entities/worker.py`:
   ```python
   @dataclass(slots=True)
   class Worker:
       id: UUID
       project_id: UUID
       name: str
       daily_rate: Decimal
       created_at: datetime
       phone: Optional[str] = None
       is_active: bool = True
       updated_at: Optional[datetime] = None
   ```
   Include `__eq__` and `__hash__` by `id`.

2. Create `app/domain/entities/labor_entry.py`:
   ```python
   @dataclass(slots=True)
   class LaborEntry:
       id: UUID
       worker_id: UUID
       date: date
       created_at: datetime
       amount_override: Optional[Decimal] = None
       note: Optional[str] = None
   ```
   Include `__eq__` and `__hash__` by `id`.

3. Create `app/domain/exceptions/labor_exceptions.py`:
   - `LaborError(Exception)` -- base
   - `WorkerNotFoundError(LaborError)` -- takes `worker_id: str`
   - `LaborEntryNotFoundError(LaborError)` -- takes `entry_id: str`
   - `DuplicateEntryError(LaborError)` -- takes `worker_id: str`, `date: str`
   - `InvalidWorkerDataError(LaborError)` -- takes `message: str`

4. Update `app/domain/entities/__init__.py` to export Worker, LaborEntry

5. Update `app/domain/exceptions/__init__.py` to export labor exceptions

6. Generate Alembic migration (or create manually):
   - `workers` table: columns matching schema, FK to `projects.id`, index on `project_id`
   - `labor_entries` table: columns matching schema, FK to `workers.id`, index on `worker_id`, UNIQUE on `(worker_id, date)`
   - `downgrade()`: drop both tables in reverse order

## Todo List

- [ ] Create Worker entity dataclass
- [ ] Create LaborEntry entity dataclass
- [ ] Create labor exceptions module
- [ ] Update domain __init__ exports
- [ ] Create Alembic migration
- [ ] Run migration to verify

## Success Criteria

- `flask db upgrade` runs without errors
- Worker and LaborEntry entities instantiable with correct types
- All exceptions importable from `app.domain.exceptions`

## Risk Assessment

- **FK integrity:** Ensure `projects.id` exists before inserting workers
- **Decimal precision:** Use `Decimal` (not `float`) throughout for EUR amounts

## Security Considerations

- No direct user input at this layer; validation happens in application/API layers
- UUID primary keys prevent enumeration attacks

## Next Steps

- Phase 02: Application layer ports and use cases consume these entities
