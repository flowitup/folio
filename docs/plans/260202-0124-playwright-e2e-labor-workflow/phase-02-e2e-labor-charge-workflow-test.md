# Phase 02: E2E Labor Charge Workflow Test

## Context Links

- [Parent Plan](./plan.md)
- [Phase 01](./phase-01-playwright-setup-and-configuration.md) (dependency)
- [Labor feature plan](../../../plans/260201-2255-labor-charge-calculator/plan.md) (completed)
- Login form: `construction-front-end/src/components/auth/LoginForm.tsx`
- Labor page: `construction-front-end/src/app/[locale]/(app)/projects/[id]/labor/page.tsx`

## Overview

- **Date:** 2026-02-02
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Write Playwright E2E spec covering full labor workflow: login → navigate to labor page → add worker → log attendance → view summary → cleanup.

## Key Insights

- No nav link to labor page exists; must navigate via direct URL `/en/projects/[id]/labor`
- Login form: `#email`, `#password` inputs, "Sign in" button
- Labor tabs: "Workers", "Attendance", "Summary" as `<button>` elements
- Add Worker dialog: name input (label "Name"), Daily Rate (label "Daily Rate"), Phone (label "Phone")
- Log Attendance dialog: worker select, date input, Rate Override input, Note input
- Delete confirmation: heading with "Delete this entry?", "Delete" button
- Deactivate confirmation: heading with "Deactivate this worker?", "Deactivate" button
- EUR formatting: French locale (`1 250,00 €` pattern)
- All text is i18n (English translations used for selectors)

## Requirements

**Functional:**
- Test logs in as admin user
- Test navigates to a seeded project's labor page
- Test creates a worker with name, daily rate, phone
- Test verifies worker appears in Workers tab
- Test logs attendance with rate override and note
- Test verifies entry in Attendance tab with correct cost
- Test verifies Summary tab shows correct totals
- Test cleans up: deletes entry, deactivates worker

**Non-functional:**
- Test runs in under 30 seconds
- Test is deterministic (unique test data with timestamps)
- Max 200 LOC per file
- Uses accessible selectors (getByRole, getByText, getByPlaceholder)

## Architecture

```
construction-front-end/e2e/
├── helpers/
│   └── auth-helper.ts                         -- (Phase 01)
└── labor-charge-full-workflow.spec.ts          -- Main E2E test
```

## Related Code Files

**Create:**
- `construction-front-end/e2e/labor-charge-full-workflow.spec.ts`

**Reference (read-only, for selector info):**
- `construction-front-end/src/components/auth/LoginForm.tsx` — login form selectors
- `construction-front-end/src/app/[locale]/(app)/projects/[id]/labor/page.tsx` — tab structure
- `construction-front-end/src/components/labor/add-worker-dialog.tsx` — worker form fields
- `construction-front-end/src/components/labor/log-attendance-dialog.tsx` — attendance form fields
- `construction-front-end/src/components/labor/worker-list.tsx` — worker display + actions
- `construction-front-end/src/components/labor/attendance-table.tsx` — entry display + delete
- `construction-front-end/src/components/labor/labor-summary.tsx` — summary display
- `construction-front-end/src/messages/en.json` — English translation keys

## Implementation Steps

1. **Create `e2e/labor-charge-full-workflow.spec.ts`:**

   **Test structure:**
   ```ts
   import { test, expect } from "@playwright/test";
   import { loginAsAdmin } from "./helpers/auth-helper";

   // Unique test data to avoid conflicts
   const WORKER_NAME = `E2E Worker ${Date.now()}`;
   const DAILY_RATE = "150.00";
   const PHONE = "0612345678";
   const OVERRIDE_AMOUNT = "175.00";
   const NOTE = "E2E test entry";

   // Project ID from seeded data (or discover dynamically)
   const PROJECT_ID = process.env.TEST_PROJECT_ID || "";

   test.describe("Labor Charge Workflow", () => {
     test.beforeEach(async ({ page }) => {
       await loginAsAdmin(page);
     });

     test("full workflow: add worker → log attendance → verify summary → cleanup", async ({ page }) => {
       // Step 1: Navigate to labor page
       // If PROJECT_ID not set, go to /projects, find first project, extract ID
       // Then navigate to /en/projects/{id}/labor

       // Step 2: Add Worker (Workers tab is default)
       // Click "Add Worker" button
       // Fill name, daily rate, phone in dialog
       // Click "Save"
       // Verify worker appears in list with correct name and rate

       // Step 3: Log Attendance (switch to Attendance tab)
       // Click "Attendance" tab
       // Click "Log Attendance" button
       // Select the worker from dropdown
       // Fill date (today), override amount, note
       // Click "Save"
       // Verify entry appears in table

       // Step 4: Verify Summary
       // Click "Summary" tab
       // Verify worker name appears with 1 day worked
       // Verify total cost matches override amount (175.00 €)

       // Step 5: Cleanup - Delete entry
       // Click "Attendance" tab
       // Click delete button on the entry
       // Confirm deletion in dialog
       // Verify entry removed

       // Step 6: Cleanup - Deactivate worker
       // Click "Workers" tab
       // Click deactivate button on the worker
       // Confirm deactivation
       // Verify worker shows "Inactive" badge
     });
   });
   ```

2. **Dynamic project discovery** (if TEST_PROJECT_ID not set):
   ```ts
   async function getFirstProjectId(page: Page): Promise<string> {
     await page.goto("/en/projects");
     await page.waitForSelector("[data-project-id]");
     const projectId = await page.getAttribute("[data-project-id]", "data-project-id");
     return projectId!;
   }
   ```
   **Note:** If projects page doesn't have `data-project-id` attribute, alternative approach:
   - Navigate to `/en/projects`
   - Click on first project card to expand
   - Extract project ID from any link/URL that contains it
   - Or use API call via `page.request.get("/api/v1/projects")` to get project ID

3. **Selector reference for implementation:**

   | Action | Selector |
   |--------|----------|
   | Login email | `page.fill("#email", email)` |
   | Login password | `page.fill("#password", password)` |
   | Sign in | `page.getByRole("button", { name: "Sign in" }).click()` |
   | Workers tab | `page.getByRole("button", { name: "Workers" }).click()` |
   | Attendance tab | `page.getByRole("button", { name: "Attendance" }).click()` |
   | Summary tab | `page.getByRole("button", { name: "Summary" }).click()` |
   | Add Worker | `page.getByRole("button", { name: "Add Worker" }).click()` |
   | Worker name input | `page.getByLabel("Name").fill(name)` |
   | Daily rate input | `page.getByLabel("Daily Rate").fill(rate)` |
   | Phone input | `page.getByLabel("Phone").fill(phone)` |
   | Save | `page.getByRole("button", { name: "Save" }).click()` |
   | Log Attendance | `page.getByRole("button", { name: "Log Attendance" }).click()` |
   | Override input | `page.getByLabel("Rate Override").fill(amount)` |
   | Note input | `page.getByLabel("Note").fill(note)` |
   | Confirm delete | `page.getByRole("button", { name: "Delete" }).click()` |
   | Confirm deactivate | `page.getByRole("button", { name: "Deactivate" }).click()` |
   | Verify worker exists | `expect(page.getByText(WORKER_NAME)).toBeVisible()` |
   | Verify cost | `expect(page.getByText(/175,00/)).toBeVisible()` |

4. **EUR format verification:**
   - French locale formats 175.00 as `175,00 €` (or `175,00\u00a0€` with non-breaking space)
   - Use regex: `/175,00/` to match regardless of spacing

## Todo List

- [ ] Create labor-charge-full-workflow.spec.ts
- [ ] Implement login step using auth helper
- [ ] Implement project navigation (direct URL or dynamic discovery)
- [ ] Implement add worker step with dialog interaction
- [ ] Implement log attendance step with dialog interaction
- [ ] Implement summary verification step
- [ ] Implement cleanup: delete entry + deactivate worker
- [ ] Run full test against Docker backend
- [ ] Verify test passes end-to-end

## Success Criteria

- `npx playwright test` passes with 1 spec, 1 test
- Test completes full workflow without manual intervention
- Test cleans up its own data (no leftover workers/entries)
- Test runs in under 30 seconds
- HTML report generated in `playwright-report/`

## Risk Assessment

- **Seeded project:** Test assumes at least one project exists. If seed fails, test fails at navigation.
- **Selector stability:** i18n text may change. Centralizing selectors in auth-helper pattern mitigates this.
- **Timing:** Dialog animations may need `waitForSelector` or small timeouts.
- **Worker dropdown in attendance:** Radix Select requires specific click pattern (trigger → option).
- **Date input:** HTML date input format may vary by locale. Use `fill()` with ISO format.

## Security Considerations

- Test credentials from env vars; defaults only for local dev
- Test data includes unique timestamp to avoid collision with real data
- Cleanup step prevents data accumulation

## Next Steps

- Run test against Docker backend to validate
- Add to CI pipeline (GitHub Actions with Docker services)
- Consider adding more E2E specs for edge cases (duplicate entry 409, permission denied)
