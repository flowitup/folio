# Brainstorm: Playwright E2E Test - Labor Charge Workflow

**Date:** 2026-02-02
**Status:** Agreed

## Problem Statement
Need Playwright E2E test simulating full labor charge workflow against real Docker backend. Flow: Login → project → labor page → add worker → log attendance → view summary → cleanup.

## Agreed Approach

- **Test runner:** @playwright/test (new install)
- **Backend:** Real via Docker (docker-compose up)
- **Auth:** Real login via UI form (admin user seeded)
- **Seed data:** Admin user + project already exist from seed script
- **Test data:** Worker + attendance created in test, cleaned after
- **Browser:** Chromium
- **Location:** `construction-front-end/e2e/labor-charge-workflow.spec.ts`

## Test Flow

1. Login as admin
2. Navigate to projects page
3. Select existing test project
4. Click "Labor" link → /projects/[id]/labor
5. Workers tab: Add worker (name, rate 150.00, phone)
6. Verify worker appears in list
7. Attendance tab: Log attendance (select worker, date, optional override)
8. Verify entry in table with correct effective cost
9. Summary tab: Verify 1 day, correct total
10. Cleanup: delete entry, deactivate worker

## Files to Create

- `construction-front-end/playwright.config.ts`
- `construction-front-end/e2e/labor-charge-workflow.spec.ts`
- `construction-front-end/e2e/helpers/auth.ts`

## Risks

- Docker must be running for tests
- Flakiness: use explicit waits and locator assertions
- Cleanup on failure: leftover test data
- CI needs Docker support
