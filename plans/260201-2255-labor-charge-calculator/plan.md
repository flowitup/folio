---
title: "Labor Charge Calculator"
description: "Track workers, daily attendance, and labor costs per construction project"
status: completed
priority: P2
effort: 6h
branch: feat/labor-charge-calculator
tags: [labor, workers, attendance, costs, backend, frontend]
created: 2026-02-01
---

# Labor Charge Calculator

Track external workers per project: manage worker profiles (name, phone, daily rate EUR), log daily attendance with optional rate override, view filterable cost summary.

## Key Decisions

- **Two tables:** `workers` (project-scoped) + `labor_entries` (daily attendance)
- **Effective cost:** `COALESCE(amount_override, daily_rate)` -- null override = default rate
- **Soft delete:** `is_active` flag on workers preserves history
- **Permission:** new `project:manage_labor` in RBAC seed
- **UNIQUE(worker_id, date):** one entry per worker per day

## Phases

| # | Phase | Effort | Status | File |
|---|-------|--------|--------|------|
| 1 | Database & Domain Layer | 0.5h | completed | [phase-01](./phase-01-database-and-domain-layer.md) |
| 2 | Application Layer (Use Cases) | 1h | completed | [phase-02](./phase-02-application-layer-use-cases.md) |
| 3 | Infrastructure Adapters | 1h | completed | [phase-03](./phase-03-infrastructure-adapters.md) |
| 4 | API Endpoints | 1h | completed | [phase-04](./phase-04-api-endpoints.md) |
| 5 | Frontend Implementation | 2h | completed | [phase-05](./phase-05-frontend-implementation.md) |
| 6 | Testing | 0.5h | completed | [phase-06](./phase-06-testing.md) |

## Dependencies

- Existing `projects` table with UUID PK
- Flask hexagonal architecture (domain/application/infrastructure/api layers)
- Next.js 16 frontend with Shadcn UI, next-intl i18n
- RBAC permission system with JWT claims

## Research Reports

- [Backend Patterns](./research/researcher-backend-patterns-report.md)
- [Frontend Patterns](./research/researcher-frontend-patterns-report.md)
- [Brainstorm](../reports/brainstorm-260201-2255-labor-charge-calculator.md)

## Validation Log

### Session 1 — 2026-02-01
**Trigger:** Initial plan creation validation
**Questions asked:** 6

#### Questions & Answers

1. **[Architecture]** The plan assumes workers are project-scoped (a worker added to Project A is separate from Project B even if same person). If the same person works on multiple projects, should they be duplicated or shared?
   - Options: Duplicated per project (Recommended) | Shared across projects
   - **Answer:** Duplicated per project
   - **Rationale:** Keeps data model simple. No cross-project worker entity needed. Each project manages its own labor independently.

2. **[Scope]** For the labor page navigation, should it be a sub-route under each project (/projects/[id]/labor) or a tab within the existing project detail view?
   - Options: Sub-route /projects/[id]/labor (Recommended) | Tab within project detail
   - **Answer:** Sub-route /projects/[id]/labor
   - **Rationale:** Dedicated page keeps project page simple, gives labor feature room to grow. Clean URL pattern.

3. **[Architecture]** The plan creates 9 separate use case files. For this feature's scope, would you prefer fewer files by combining worker + entry operations?
   - Options: 9 separate files (plan as-is) | 2 files: worker_usecases.py + entry_usecases.py | 3 files: worker + entry + summary
   - **Answer:** 9 separate files (plan as-is)
   - **Rationale:** Matches existing project CRUD pattern exactly. Single-responsibility per file. Consistent codebase.

4. **[Scope]** Should the attendance log support bulk entry (mark multiple workers present for the same day in one request)?
   - Options: Single entry only (MVP) | Bulk entry (array of workers per day)
   - **Answer:** Single entry only (MVP)
   - **Rationale:** Simpler to implement and test. Bulk entry can be added later if UX requires it.

5. **[Tradeoff]** For the frontend summary table, should costs be formatted as EUR using French locale (1 250,00 €) or standard (€1,250.00)?
   - Options: French locale: 1 250,00 € | Standard: €1,250.00 | Follow browser locale
   - **Answer:** French locale: 1 250,00 €
   - **Rationale:** User timezone is Europe/Paris. French number formatting matches business context.

6. **[Architecture]** The plan puts standalone update/delete routes at /workers/{id} and /labor-entries/{id}. Should these stay project-nested for consistency?
   - Options: Standalone routes (plan as-is) | All nested under project (Recommended)
   - **Answer:** All nested under project
   - **Rationale:** Consistent URL pattern. Backend can verify worker/entry belongs to project. Extra safety layer.

#### Confirmed Decisions
- **Worker scope:** Duplicated per project — simple, no cross-project entity
- **Navigation:** Sub-route `/projects/[id]/labor` — dedicated page
- **File granularity:** 9 separate use case files — matches existing pattern
- **Bulk entry:** Single entry MVP — keep simple
- **EUR format:** French locale (1 250,00 €) — matches user context

#### Action Items
- [ ] Update Phase 04: Change standalone routes (`/workers/{id}`, `/labor-entries/{id}`) to project-nested (`/projects/{pid}/workers/{wid}`, `/projects/{pid}/labor-entries/{eid}`)
- [ ] Update Phase 05: Add French EUR formatter (`Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })`)

#### Impact on Phases
- **Phase 04:** Route paths must change from `/workers/{id}` and `/labor-entries/{id}` to `/projects/{pid}/workers/{wid}` and `/projects/{pid}/labor-entries/{eid}`. All update/delete endpoints become project-scoped. Use case calls must pass project_id for ownership verification.
- **Phase 05:** EUR formatting must use `fr-FR` locale. Update `formatCurrency` or create `formatEUR()` utility.
