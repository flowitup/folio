# Brainstorm: Labor Charge Calculator

**Date:** 2026-02-01
**Status:** Agreed
**Approach:** A - Two Tables (Workers + Labor Entries)

## Problem Statement

Construction projects need to track external workers (not system users), daily attendance, and labor costs per project. Workers have default daily rate (EUR) with per-day override. Managers need filterable table to view/export labor costs.

## Requirements

| Aspect | Decision |
|--------|----------|
| Worker type | External labor (no account) |
| Worker data | Name + phone (minimal) |
| Day tracking | Daily attendance log |
| Rate model | Fixed daily rate + per-day override |
| Scope | Per project |
| Currency | EUR |
| Reporting | Filterable table (date range, worker) |

## Agreed Solution: Approach A

### Database Schema

```sql
workers
├── id: UUID (PK)
├── project_id: UUID (FK → projects, NOT NULL)
├── name: VARCHAR(255, NOT NULL)
├── phone: VARCHAR(50, nullable)
├── daily_rate: DECIMAL(10,2, NOT NULL) -- default EUR rate
├── is_active: BOOLEAN (default true, soft delete)
├── created_at: TIMESTAMP
├── updated_at: TIMESTAMP

labor_entries
├── id: UUID (PK)
├── worker_id: UUID (FK → workers, NOT NULL)
├── date: DATE (NOT NULL)
├── amount_override: DECIMAL(10,2, nullable) -- null = use worker.daily_rate
├── note: VARCHAR(500, nullable)
├── created_at: TIMESTAMP
├── UNIQUE(worker_id, date) -- one entry per worker per day
```

**Effective cost:** `COALESCE(labor_entries.amount_override, workers.daily_rate)`

### API Endpoints

| Method | Endpoint | Permission |
|--------|----------|------------|
| GET | `/projects/{id}/workers` | project:read |
| POST | `/projects/{id}/workers` | project:manage_labor |
| PUT | `/workers/{id}` | project:manage_labor |
| DELETE | `/workers/{id}` | project:manage_labor |
| GET | `/projects/{id}/labor-entries?from=&to=&worker_id=` | project:read |
| POST | `/projects/{id}/labor-entries` | project:manage_labor |
| PUT | `/labor-entries/{id}` | project:manage_labor |
| DELETE | `/labor-entries/{id}` | project:manage_labor |
| GET | `/projects/{id}/labor-summary?from=&to=` | project:read |

### Backend Architecture (Hexagonal)

```
Domain:        entities/worker.py, entities/labor_entry.py
Application:   labor/ports.py, labor/create_worker.py, labor/log_attendance.py, labor/list_entries.py
Infrastructure: models/worker.py, models/labor_entry.py, adapters/sqlalchemy_worker.py, adapters/sqlalchemy_labor_entry.py
API:           api/v1/labor/routes.py, api/v1/labor/schemas.py
```

### Frontend Architecture

```
/[locale]/(app)/projects/[id]/labor/page.tsx
components/labor/
├── worker-list.tsx
├── attendance-table.tsx
├── labor-summary.tsx
└── add-worker-dialog.tsx
```

### Key Decisions

- **COALESCE pattern:** null override = use default rate (simple, no extra logic)
- **UNIQUE(worker_id, date):** prevents double entries per day
- **Soft delete (is_active):** deactivate workers without losing history
- **Permission:** new `project:manage_labor` permission in RBAC
- **DECIMAL(10,2):** EUR precision

### Risks

- RBAC seed needs `project:manage_labor` permission added
- Bulk attendance entry (multiple workers same day) desirable for UX
- CSV export not in MVP but plan for it
- Date timezone handling: store UTC, display local

### Evaluated Alternatives

| Approach | Verdict |
|----------|---------|
| A: Workers + Labor Entries (2 tables) | **Selected** - clean, normalized, flexible |
| B: Single denormalized table | Rejected - DRY violation, no worker reuse |
| C: Three tables + rate history | Rejected - YAGNI, over-engineered |
