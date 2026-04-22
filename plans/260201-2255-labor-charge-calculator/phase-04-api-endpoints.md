# Phase 04: API Endpoints

## Context Links

- [Parent Plan](./plan.md)
- [Phase 03](./phase-03-infrastructure-adapters.md) (dependency)
- Reference: `app/api/v1/projects/routes.py`, `schemas.py`, `decorators.py`

## Overview

- **Date:** 2026-02-01
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Create Flask blueprint with 9 REST endpoints for worker and labor entry management, plus Pydantic request/response schemas.

## Key Insights

- Blueprint pattern: `Blueprint("labor", __name__, url_prefix="/labor")`
- Register under `/api/v1/projects/<project_id>/labor` for project-scoped endpoints
- Standalone worker/entry endpoints: `/api/v1/workers/<id>`, `/api/v1/labor-entries/<id>`
- Decorator stack: `@jwt_required()` -> `@limiter.limit()` -> `@require_permission()`
- Reuse `require_permission` and `ErrorResponse` from projects module
- Pydantic validation with `Field()` constraints

## Requirements

**Functional:**
9 endpoints as specified:
1. `GET /projects/{id}/workers` -- list project workers
2. `POST /projects/{id}/workers` -- create worker
3. `PUT /workers/{id}` -- update worker
4. `DELETE /workers/{id}` -- soft delete worker
5. `GET /projects/{id}/labor-entries?from=&to=&worker_id=` -- list entries
6. `POST /projects/{id}/labor-entries` -- log attendance
7. `PUT /labor-entries/{id}` -- update entry
8. `DELETE /labor-entries/{id}` -- delete entry
9. `GET /projects/{id}/labor-summary?from=&to=` -- aggregated summary

**Non-functional:**
- Rate limiting: 10/min for writes, no limit for reads
- Consistent error responses using ErrorResponse schema
- Each file under 200 lines (split routes into workers + entries if needed)

## Architecture

```
app/api/v1/labor/
  __init__.py          -- Blueprint definition
  schemas.py           -- Pydantic request/response models
  worker_routes.py     -- Worker CRUD endpoints (4 routes)
  entry_routes.py      -- Labor entry CRUD + summary endpoints (5 routes)
```

Separate route files keep each under 200 lines.

## Related Code Files

**Create:**
- `construction-back-end/app/api/v1/labor/__init__.py`
- `construction-back-end/app/api/v1/labor/schemas.py`
- `construction-back-end/app/api/v1/labor/worker_routes.py`
- `construction-back-end/app/api/v1/labor/entry_routes.py`

**Modify:**
- `construction-back-end/app/__init__.py` -- register labor blueprint

## Implementation Steps

1. **Create `labor/__init__.py`:**
   ```python
   from flask import Blueprint
   labor_bp = Blueprint("labor", __name__)
   from app.api.v1.labor import worker_routes, entry_routes  # noqa
   ```

2. **Create `labor/schemas.py`:**
   ```python
   # Request schemas
   class CreateWorkerRequest(BaseModel):
       name: str = Field(..., min_length=1, max_length=255)
       daily_rate: float = Field(..., gt=0)
       phone: Optional[str] = Field(None, max_length=50)

   class UpdateWorkerRequest(BaseModel):
       name: Optional[str] = Field(None, min_length=1, max_length=255)
       daily_rate: Optional[float] = Field(None, gt=0)
       phone: Optional[str] = Field(None, max_length=50)

   class LogAttendanceRequest(BaseModel):
       worker_id: str = Field(...)
       date: str = Field(...)  # ISO date YYYY-MM-DD
       amount_override: Optional[float] = Field(None, ge=0)
       note: Optional[str] = Field(None, max_length=500)

   class UpdateAttendanceRequest(BaseModel):
       amount_override: Optional[float] = Field(None, ge=0)
       note: Optional[str] = Field(None, max_length=500)

   # Response schemas
   class WorkerResponse(BaseModel):
       id: str
       project_id: str
       name: str
       phone: Optional[str]
       daily_rate: float
       is_active: bool
       created_at: str

   class WorkerListResponse(BaseModel):
       workers: List[WorkerResponse]
       total: int

   class LaborEntryResponse(BaseModel):
       id: str
       worker_id: str
       worker_name: str
       date: str
       amount_override: Optional[float]
       effective_cost: float
       note: Optional[str]
       created_at: str

   class LaborEntryListResponse(BaseModel):
       entries: List[LaborEntryResponse]
       total: int

   class WorkerSummaryRow(BaseModel):
       worker_id: str
       worker_name: str
       days_worked: int
       total_cost: float

   class LaborSummaryResponse(BaseModel):
       rows: List[WorkerSummaryRow]
       total_days: int
       total_cost: float
   ```

3. **Create `labor/worker_routes.py`:**
   - `GET /projects/<project_id>/workers` -- `@require_permission("project:read")`
     - Call `list_workers_usecase.execute(project_id)`
   - `POST /projects/<project_id>/workers` -- `@require_permission("project:manage_labor")`, `@limiter.limit("10 per minute")`
     - Parse CreateWorkerRequest, call create_worker_usecase
   - `PUT /workers/<worker_id>` -- `@require_permission("project:manage_labor")`, `@limiter.limit("10 per minute")`
     - Parse UpdateWorkerRequest, call update_worker_usecase
   - `DELETE /workers/<worker_id>` -- `@require_permission("project:manage_labor")`, `@limiter.limit("10 per minute")`
     - Call delete_worker_usecase (soft delete), return 204

4. **Create `labor/entry_routes.py`:**
   - `GET /projects/<project_id>/labor-entries` -- `@require_permission("project:read")`
     - Parse query params: `from`, `to`, `worker_id`
     - Call list_labor_entries_usecase
   - `POST /projects/<project_id>/labor-entries` -- `@require_permission("project:manage_labor")`, `@limiter.limit("10 per minute")`
     - Parse LogAttendanceRequest, call log_attendance_usecase
     - Catch DuplicateEntryError -> 409 Conflict
   - `PUT /labor-entries/<entry_id>` -- `@require_permission("project:manage_labor")`, `@limiter.limit("10 per minute")`
     - Parse UpdateAttendanceRequest, call update_attendance_usecase
   - `DELETE /labor-entries/<entry_id>` -- `@require_permission("project:manage_labor")`, `@limiter.limit("10 per minute")`
     - Call delete_attendance_usecase, return 204
   - `GET /projects/<project_id>/labor-summary` -- `@require_permission("project:read")`
     - Parse query params: `from`, `to`
     - Call get_labor_summary_usecase

5. **Update `app/__init__.py`:**
   - Import `labor_bp` from `app.api.v1.labor`
   - Register: `app.register_blueprint(labor_bp, url_prefix="/api/v1")`
   - Worker routes use `/projects/<id>/workers` and `/workers/<id>` prefixes within the blueprint
   - Entry routes use `/projects/<id>/labor-entries`, `/labor-entries/<id>`, `/projects/<id>/labor-summary`

## Todo List

- [ ] Create labor blueprint __init__.py
- [ ] Create schemas.py with all request/response models
- [ ] Create worker_routes.py (4 endpoints)
- [ ] Create entry_routes.py (5 endpoints)
- [ ] Register blueprint in app factory
- [ ] Test all endpoints return correct status codes manually

## Success Criteria

- All 9 endpoints accessible with correct permissions
- Validation errors return 400 with ErrorResponse format
- DuplicateEntryError returns 409 Conflict
- NotFound errors return 404
- Rate limiting applied to write operations

## Risk Assessment

- **URL routing conflicts:** Standalone routes (`/workers/<id>`, `/labor-entries/<id>`) need careful blueprint prefix planning to avoid conflict with project-scoped routes
- **Date parsing:** ISO date strings from query params must be validated

## Security Considerations

- `@jwt_required()` on all endpoints
- `@require_permission("project:manage_labor")` for all write ops
- `@require_permission("project:read")` for all read ops
- Rate limiting prevents abuse
- Input validation via Pydantic prevents injection

## Next Steps

- Phase 05: Frontend consumes these endpoints
