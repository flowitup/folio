# Phase 02: Application Layer (Use Cases)

## Context Links

- [Parent Plan](./plan.md)
- [Phase 01](./phase-01-database-and-domain-layer.md) (dependency)
- [Backend Patterns Report](./research/researcher-backend-patterns-report.md)
- Reference: `app/application/projects/` for pattern

## Overview

- **Date:** 2026-02-01
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Define repository port interfaces and use case classes for worker and labor entry CRUD, plus labor summary aggregation.

## Key Insights

- Ports: `ABC` with `@abstractmethod`, return domain entities not DTOs
- Use cases: single `execute()` method, take request dataclass, return response dataclass
- Follow `app/application/projects/` package structure (ports.py, create.py, list.py, etc.)
- Each use case in its own file, `__init__.py` re-exports all

## Requirements

**Functional:**
- IWorkerRepository: create, find_by_id, list_by_project, update, soft_delete
- ILaborEntryRepository: create, find_by_id, list_by_project (with date/worker filters), update, delete, get_summary
- Use cases: CreateWorker, UpdateWorker, DeleteWorker, LogAttendance, UpdateAttendance, DeleteAttendance, ListWorkers, ListLaborEntries, GetLaborSummary

**Non-functional:**
- Type hints on all public methods
- Google-style docstrings
- Each file under 200 lines

## Architecture

```
app/application/labor/
  __init__.py              -- re-exports
  ports.py                 -- IWorkerRepository, ILaborEntryRepository
  create_worker.py         -- CreateWorkerUseCase
  update_worker.py         -- UpdateWorkerUseCase
  delete_worker.py         -- DeleteWorkerUseCase (soft delete)
  log_attendance.py        -- LogAttendanceUseCase
  update_attendance.py     -- UpdateAttendanceUseCase
  delete_attendance.py     -- DeleteAttendanceUseCase
  list_workers.py          -- ListWorkersUseCase
  list_labor_entries.py    -- ListLaborEntriesUseCase
  get_labor_summary.py     -- GetLaborSummaryUseCase
```

## Related Code Files

**Create:**
- `construction-back-end/app/application/labor/__init__.py`
- `construction-back-end/app/application/labor/ports.py`
- `construction-back-end/app/application/labor/create_worker.py`
- `construction-back-end/app/application/labor/update_worker.py`
- `construction-back-end/app/application/labor/delete_worker.py`
- `construction-back-end/app/application/labor/log_attendance.py`
- `construction-back-end/app/application/labor/update_attendance.py`
- `construction-back-end/app/application/labor/delete_attendance.py`
- `construction-back-end/app/application/labor/list_workers.py`
- `construction-back-end/app/application/labor/list_labor_entries.py`
- `construction-back-end/app/application/labor/get_labor_summary.py`

## Implementation Steps

1. **Create `ports.py`** with two interfaces:
   ```python
   class IWorkerRepository(ABC):
       def create(self, worker: Worker) -> Worker: ...
       def find_by_id(self, worker_id: UUID) -> Optional[Worker]: ...
       def list_by_project(self, project_id: UUID, active_only: bool = True) -> List[Worker]: ...
       def update(self, worker: Worker) -> Worker: ...
       def soft_delete(self, worker_id: UUID) -> bool: ...

   class ILaborEntryRepository(ABC):
       def create(self, entry: LaborEntry) -> LaborEntry: ...
       def find_by_id(self, entry_id: UUID) -> Optional[LaborEntry]: ...
       def list_by_project(self, project_id: UUID, date_from: Optional[date], date_to: Optional[date], worker_id: Optional[UUID]) -> List[LaborEntry]: ...
       def update(self, entry: LaborEntry) -> LaborEntry: ...
       def delete(self, entry_id: UUID) -> bool: ...
       def get_summary(self, project_id: UUID, date_from: Optional[date], date_to: Optional[date]) -> List[LaborSummaryRow]: ...
   ```

2. **Create `create_worker.py`:**
   - Request: `name: str, daily_rate: Decimal, project_id: UUID, phone: Optional[str]`
   - Validate name non-empty, daily_rate > 0
   - Create Worker entity with `uuid4()`, `datetime.now(UTC)`
   - Return response DTO with string IDs

3. **Create `update_worker.py`:**
   - Request: `worker_id: UUID, name: Optional[str], phone: Optional[str], daily_rate: Optional[Decimal]`
   - Find worker or raise WorkerNotFoundError
   - Update only provided fields
   - Return updated response DTO

4. **Create `delete_worker.py`:**
   - Request: `worker_id: UUID`
   - Soft delete via `is_active = False`
   - Raise WorkerNotFoundError if not found

5. **Create `log_attendance.py`:**
   - Request: `worker_id: UUID, project_id: UUID, date: date, amount_override: Optional[Decimal], note: Optional[str]`
   - Verify worker exists and belongs to project
   - Create LaborEntry; catch DB unique constraint -> raise DuplicateEntryError
   - Return response DTO

6. **Create `update_attendance.py`:**
   - Request: `entry_id: UUID, amount_override: Optional[Decimal], note: Optional[str]`
   - Find entry or raise LaborEntryNotFoundError
   - Return updated response DTO

7. **Create `delete_attendance.py`:**
   - Request: `entry_id: UUID`
   - Delete entry or raise LaborEntryNotFoundError

8. **Create `list_workers.py`:**
   - Request: `project_id: UUID`
   - Return list of worker response DTOs

9. **Create `list_labor_entries.py`:**
   - Request: `project_id: UUID, date_from: Optional[date], date_to: Optional[date], worker_id: Optional[UUID]`
   - Return list of entry response DTOs (include worker_name, effective_cost)

10. **Create `get_labor_summary.py`:**
    - Request: `project_id: UUID, date_from: Optional[date], date_to: Optional[date]`
    - Return aggregated summary: per worker (name, days_worked, total_cost)
    - Add project total_cost and total_days

11. **Create `__init__.py`** re-exporting all use cases and ports

## Todo List

- [ ] Create ports.py with IWorkerRepository and ILaborEntryRepository
- [ ] Create CreateWorkerUseCase
- [ ] Create UpdateWorkerUseCase
- [ ] Create DeleteWorkerUseCase (soft delete)
- [ ] Create LogAttendanceUseCase
- [ ] Create UpdateAttendanceUseCase
- [ ] Create DeleteAttendanceUseCase
- [ ] Create ListWorkersUseCase
- [ ] Create ListLaborEntriesUseCase
- [ ] Create GetLaborSummaryUseCase
- [ ] Create __init__.py with all exports

## Success Criteria

- All use cases importable from `app.application.labor`
- Each file under 200 lines
- Type hints on all public methods
- Domain exceptions raised for invalid operations

## Risk Assessment

- **DuplicateEntryError:** Must be caught from DB constraint violation in adapter, re-raised as domain exception
- **Project ownership:** LogAttendance must verify worker.project_id == request.project_id

## Security Considerations

- Use cases do not handle auth; that's the API layer's job
- Validate rate > 0 to prevent negative cost entries

## Next Steps

- Phase 03: Infrastructure adapters implement these port interfaces
