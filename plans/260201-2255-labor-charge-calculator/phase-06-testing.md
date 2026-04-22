# Phase 06: Testing

## Context Links

- [Parent Plan](./plan.md)
- All previous phases (dependency)
- Reference: `tests/test_project_usecases.py`, `tests/test_project_repository.py`
- Reference: `src/components/project/__tests__/ProjectSelector.test.tsx`

## Overview

- **Date:** 2026-02-01
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Write backend pytest tests for use cases and API endpoints, and frontend Vitest tests for components and API client.

## Key Insights

- Backend tests: pytest with fixtures in `conftest.py`, mock repositories for unit tests
- Existing test patterns: `test_project_usecases.py` for use case testing, `test_project_repository.py` for adapter testing
- Frontend tests: Vitest with `@testing-library/react`
- Test files co-located in `__tests__/` directories or `tests/` at project root

## Requirements

**Functional:**
- Backend unit tests: all 9 use cases
- Backend integration tests: all 9 API endpoints
- Frontend unit tests: key components and API client

**Non-functional:**
- No mocking of business logic (only external dependencies like DB session)
- Real domain exceptions tested
- Edge cases: duplicate entry, not found, invalid data, permission denied

## Architecture

```
Backend:
  tests/
    test_labor_usecases.py      -- Unit tests for all 9 use cases
    test_labor_endpoints.py     -- Integration tests for API routes

Frontend:
  src/components/labor/__tests__/
    worker-list.test.tsx
    attendance-table.test.tsx
    labor-summary.test.tsx
  src/lib/api/__tests__/
    labor.test.ts
```

## Related Code Files

**Create:**
- `construction-back-end/tests/test_labor_usecases.py`
- `construction-back-end/tests/test_labor_endpoints.py`
- `construction-front-end/src/components/labor/__tests__/worker-list.test.tsx`
- `construction-front-end/src/components/labor/__tests__/attendance-table.test.tsx`
- `construction-front-end/src/components/labor/__tests__/labor-summary.test.tsx`
- `construction-front-end/src/lib/api/__tests__/labor.test.ts`

**Modify:**
- `construction-back-end/tests/conftest.py` -- add labor fixtures if needed

## Implementation Steps

### Backend Tests

1. **Create `test_labor_usecases.py`** -- mock repositories, test each use case:

   **CreateWorkerUseCase:**
   - test_create_worker_success
   - test_create_worker_empty_name_raises_error
   - test_create_worker_negative_rate_raises_error

   **UpdateWorkerUseCase:**
   - test_update_worker_success
   - test_update_worker_not_found_raises_error

   **DeleteWorkerUseCase:**
   - test_soft_delete_worker_success
   - test_delete_worker_not_found_raises_error

   **LogAttendanceUseCase:**
   - test_log_attendance_success
   - test_log_attendance_duplicate_raises_error
   - test_log_attendance_worker_not_found_raises_error
   - test_log_attendance_with_override

   **UpdateAttendanceUseCase:**
   - test_update_attendance_success
   - test_update_attendance_not_found_raises_error

   **DeleteAttendanceUseCase:**
   - test_delete_attendance_success
   - test_delete_attendance_not_found_raises_error

   **ListWorkersUseCase:**
   - test_list_workers_returns_active_only
   - test_list_workers_empty_project

   **ListLaborEntriesUseCase:**
   - test_list_entries_no_filters
   - test_list_entries_with_date_range
   - test_list_entries_with_worker_filter

   **GetLaborSummaryUseCase:**
   - test_summary_aggregates_correctly
   - test_summary_uses_override_when_present
   - test_summary_empty_project

2. **Create `test_labor_endpoints.py`** -- Flask test client, JWT fixtures:

   **Worker endpoints:**
   - test_list_workers_200
   - test_create_worker_201
   - test_create_worker_validation_error_400
   - test_create_worker_no_permission_403
   - test_update_worker_200
   - test_update_worker_not_found_404
   - test_delete_worker_204
   - test_delete_worker_not_found_404

   **Entry endpoints:**
   - test_list_entries_200
   - test_list_entries_with_filters_200
   - test_log_attendance_201
   - test_log_attendance_duplicate_409
   - test_log_attendance_no_permission_403
   - test_update_entry_200
   - test_delete_entry_204

   **Summary endpoint:**
   - test_labor_summary_200
   - test_labor_summary_with_date_range_200

### Frontend Tests

3. **Create `worker-list.test.tsx`:**
   - test renders worker list with correct data
   - test shows empty state when no workers
   - test hides action buttons without manage_labor permission
   - test shows action buttons with manage_labor permission

4. **Create `attendance-table.test.tsx`:**
   - test renders entries with correct columns
   - test displays effective cost (override vs default)
   - test shows empty state

5. **Create `labor-summary.test.tsx`:**
   - test renders summary rows
   - test displays grand total correctly
   - test shows empty state

6. **Create `labor.test.ts`** (API client):
   - test fetchWorkers calls correct endpoint
   - test createWorker sends correct payload
   - test fetchLaborEntries passes query params
   - test fetchLaborSummary passes date range params

## Todo List

- [ ] Create test_labor_usecases.py (backend unit tests)
- [ ] Create test_labor_endpoints.py (backend integration tests)
- [ ] Create worker-list.test.tsx
- [ ] Create attendance-table.test.tsx
- [ ] Create labor-summary.test.tsx
- [ ] Create labor.test.ts (API client tests)
- [ ] Run backend tests: `pytest tests/test_labor_*`
- [ ] Run frontend tests: `npx vitest run --reporter=verbose`
- [ ] Verify all tests pass

## Success Criteria

- All backend tests pass with `pytest`
- All frontend tests pass with `vitest`
- Use case tests cover: success, not found, validation error, duplicate entry
- Endpoint tests cover: 200, 201, 204, 400, 403, 404, 409 status codes
- No mocked business logic; only mock infrastructure (DB session, fetch)

## Risk Assessment

- **Test DB setup:** Integration tests may need a test database; check `conftest.py` for existing patterns
- **JWT mocking:** Need fixtures to simulate authenticated requests with specific permissions

## Security Considerations

- Test that endpoints without proper JWT return 401
- Test that endpoints without proper permission return 403
- Test that users cannot access other projects' labor data

## Next Steps

- All phases complete; feature ready for code review and merge
