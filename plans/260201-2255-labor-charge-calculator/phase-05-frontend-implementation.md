# Phase 05: Frontend Implementation

## Context Links

- [Parent Plan](./plan.md)
- [Phase 04](./phase-04-api-endpoints.md) (dependency)
- [Frontend Patterns Report](./research/researcher-frontend-patterns-report.md)
- Reference: `src/app/[locale]/(app)/projects/page.tsx`, `src/lib/api/projects.ts`

## Overview

- **Date:** 2026-02-01
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Build the labor management UI: types, API client, page route, components (worker list, attendance table, summary view, dialogs), i18n translations, and navigation link.

## Key Insights

- Pages: `"use client"`, `useTranslations()`, context hooks
- API client: typed `api.get/post/put/delete` from `@/lib/api/http`
- Components: Shadcn UI (Button, Card, Dialog, Input, Select, Alert, Badge, AlertDialog, Label, Separator, DropdownMenu all available)
- Permission check: `user?.permissions?.some(p => p === "project:manage_labor" || p === "*:*")`
- i18n: namespace-based keys in `src/messages/{en,vi,fr}.json`
- Follow `AddMemberDialog` pattern for form dialogs

## Requirements

**Functional:**
- Labor page accessible at `/projects/[id]/labor` (nested under project)
- Worker management: list, add, edit, deactivate workers
- Attendance logging: date picker, worker select, optional rate override, note
- Summary table: filterable by date range, shows per-worker totals + grand total
- Permission-gated write actions

**Non-functional:**
- Loading/error/empty states for all data sections
- Responsive design (mobile-friendly table)
- i18n for English, Vietnamese, French

## Architecture

```
src/
  types/labor.ts                              -- TS interfaces
  lib/api/labor.ts                            -- API client functions
  app/[locale]/(app)/projects/[id]/labor/
    page.tsx                                  -- Main labor page
  components/labor/
    worker-list.tsx                           -- Worker cards/list
    add-worker-dialog.tsx                     -- Add/edit worker form
    attendance-table.tsx                      -- Daily entries table
    log-attendance-dialog.tsx                 -- Log attendance form
    labor-summary.tsx                         -- Summary aggregation view
  messages/en.json                            -- Add "labor" namespace
  messages/vi.json                            -- Add "labor" namespace
  messages/fr.json                            -- Add "labor" namespace
```

## Related Code Files

**Create:**
- `construction-front-end/src/types/labor.ts`
- `construction-front-end/src/lib/api/labor.ts`
- `construction-front-end/src/app/[locale]/(app)/projects/[id]/labor/page.tsx`
- `construction-front-end/src/components/labor/worker-list.tsx`
- `construction-front-end/src/components/labor/add-worker-dialog.tsx`
- `construction-front-end/src/components/labor/attendance-table.tsx`
- `construction-front-end/src/components/labor/log-attendance-dialog.tsx`
- `construction-front-end/src/components/labor/labor-summary.tsx`

**Modify:**
- `construction-front-end/src/messages/en.json` -- add `labor` namespace
- `construction-front-end/src/messages/vi.json` -- add `labor` namespace
- `construction-front-end/src/messages/fr.json` -- add `labor` namespace
- `construction-front-end/src/components/layout/Sidebar.tsx` -- add labor nav item (or add link from project detail)

## Implementation Steps

1. **Create `types/labor.ts`:**
   ```ts
   export interface Worker {
     id: string; project_id: string; name: string;
     phone: string | null; daily_rate: number;
     is_active: boolean; created_at: string;
   }
   export interface WorkerListResponse { workers: Worker[]; total: number; }
   export interface LaborEntry {
     id: string; worker_id: string; worker_name: string;
     date: string; amount_override: number | null;
     effective_cost: number; note: string | null; created_at: string;
   }
   export interface LaborEntryListResponse { entries: LaborEntry[]; total: number; }
   export interface WorkerSummaryRow {
     worker_id: string; worker_name: string;
     days_worked: number; total_cost: number;
   }
   export interface LaborSummaryResponse {
     rows: WorkerSummaryRow[]; total_days: number; total_cost: number;
   }
   ```

2. **Create `lib/api/labor.ts`:**
   ```ts
   export async function fetchWorkers(projectId: string): Promise<Worker[]>
   export async function createWorker(projectId: string, data: CreateWorkerPayload): Promise<Worker>
   export async function updateWorker(workerId: string, data: UpdateWorkerPayload): Promise<Worker>
   export async function deleteWorker(workerId: string): Promise<void>
   export async function fetchLaborEntries(projectId: string, params?: LaborEntryParams): Promise<LaborEntry[]>
   export async function logAttendance(projectId: string, data: LogAttendancePayload): Promise<LaborEntry>
   export async function updateAttendance(entryId: string, data: UpdateAttendancePayload): Promise<LaborEntry>
   export async function deleteAttendance(entryId: string): Promise<void>
   export async function fetchLaborSummary(projectId: string, params?: SummaryParams): Promise<LaborSummaryResponse>
   ```

3. **Create `projects/[id]/labor/page.tsx`:**
   - `"use client"`, get `id` from params
   - Tab/section layout: Workers | Attendance | Summary
   - Use `useProject()` for project context, `useAuth()` for permissions
   - Permission check: `canManageLabor` for showing add/edit/delete buttons
   - Fetch workers on mount, entries/summary on tab switch or filter change

4. **Create `components/labor/worker-list.tsx`:**
   - Display workers as list with name, phone, daily rate, active status
   - Edit/deactivate actions (permission-gated)
   - Empty state when no workers

5. **Create `components/labor/add-worker-dialog.tsx`:**
   - Dialog with form: name (required), phone (optional), daily_rate (required, number)
   - Follow `AddMemberDialog` pattern
   - Reuse for edit mode (pass existing worker data)

6. **Create `components/labor/attendance-table.tsx`:**
   - Table: date, worker name, effective cost (with override indicator), note, actions
   - Date range filter inputs (from/to)
   - Worker filter dropdown
   - Delete action (permission-gated)

7. **Create `components/labor/log-attendance-dialog.tsx`:**
   - Dialog form: worker select, date input, amount_override (optional), note (optional)
   - Worker dropdown populated from project workers list
   - Handle 409 Conflict (duplicate entry) with user-friendly message

8. **Create `components/labor/labor-summary.tsx`:**
   - Table: worker name, days worked, total cost
   - Footer row: grand total
   - Date range filter inputs
   - Format costs as EUR with 2 decimals

9. **Update i18n files** (`en.json`, `vi.json`, `fr.json`):
   Add `"labor"` namespace with keys:
   ```json
   "labor": {
     "title": "Labor Charges",
     "workers": "Workers",
     "attendance": "Attendance",
     "summary": "Summary",
     "addWorker": "Add Worker",
     "editWorker": "Edit Worker",
     "deactivateWorker": "Deactivate",
     "workerName": "Name",
     "workerPhone": "Phone",
     "dailyRate": "Daily Rate",
     "noWorkers": "No workers added yet",
     "logAttendance": "Log Attendance",
     "date": "Date",
     "override": "Rate Override",
     "note": "Note",
     "effectiveCost": "Cost",
     "noEntries": "No entries found",
     "duplicateEntry": "This worker already has an entry for this date",
     "daysWorked": "Days",
     "totalCost": "Total",
     "grandTotal": "Grand Total",
     "filterFrom": "From",
     "filterTo": "To",
     "filterWorker": "Worker",
     "confirmDeactivate": "Deactivate this worker?",
     "confirmDelete": "Delete this entry?",
     "cancel": "Cancel",
     "save": "Save",
     "delete": "Delete",
     "active": "Active",
     "inactive": "Inactive"
   }
   ```

10. **Update `Sidebar.tsx`** or add project sub-navigation:
    - Option A: Add "Labor" as sub-item under Projects in sidebar
    - Option B: Add a "Labor Charges" link/tab on the project detail page
    - Recommendation: Option B (labor is project-scoped, not a top-level nav item). Add a navigation link from the project card or project detail view to `/projects/[id]/labor`.

## Todo List

- [ ] Create labor TypeScript types
- [ ] Create labor API client functions
- [ ] Create labor page route
- [ ] Create worker-list component
- [ ] Create add-worker-dialog component
- [ ] Create attendance-table component
- [ ] Create log-attendance-dialog component
- [ ] Create labor-summary component
- [ ] Add i18n translations (en, vi, fr)
- [ ] Add navigation to labor page from project

## Success Criteria

- Labor page renders at `/[locale]/projects/[id]/labor`
- Workers CRUD works with proper permission gating
- Attendance logging handles duplicate entry (409) gracefully
- Summary shows correct aggregated costs
- All text uses i18n translations
- Loading/error/empty states present

## Risk Assessment

- **Project ID routing:** Next.js dynamic route `[id]` must resolve correctly nested under projects
- **Date handling:** Ensure consistent ISO date format between frontend and API
- **Missing Shadcn components:** May need to add `Table` or `Tabs` components via `npx shadcn-ui add`

## Security Considerations

- Permission checks in UI hide write actions from unauthorized users
- API client sends JWT; backend enforces actual authorization
- No sensitive data displayed (worker phone partially visible)

## Next Steps

- Phase 06: Testing for both backend and frontend
