# Phase 01: Playwright Setup & Configuration

## Context Links

- [Parent Plan](./plan.md)
- [Brainstorm](../../plans/260201-2255-labor-charge-calculator/reports/brainstorm-260202-0112-playwright-e2e-labor-workflow.md)
- Frontend: `construction-front-end/`

## Overview

- **Date:** 2026-02-02
- **Priority:** P2
- **Status:** pending
- **Review:** not started
- **Description:** Install Playwright, create config, auth helper, and update package.json/gitignore.

## Key Insights

- Vitest already handles unit tests; Playwright is additive (no conflict)
- Chromium-only for speed; add Firefox/WebKit later if needed
- `webServer` config can auto-start Next.js dev server
- Auth helper reusable across future E2E specs

## Requirements

**Functional:**
- `npx playwright test` runs E2E tests from `e2e/` directory
- Auth helper logs in via UI form and persists session
- Config reads baseURL from env var (default http://localhost:3000)

**Non-functional:**
- Chromium only (fast CI)
- Retries: 0 locally, 2 in CI
- Screenshots on failure
- Max 200 LOC per file

## Architecture

```
construction-front-end/
├── playwright.config.ts          -- Playwright configuration
├── e2e/
│   └── helpers/
│       └── auth-helper.ts        -- Login helper function
├── package.json                  -- Add devDep + script
└── .gitignore                    -- Add playwright artifacts
```

## Related Code Files

**Create:**
- `construction-front-end/playwright.config.ts`
- `construction-front-end/e2e/helpers/auth-helper.ts`

**Modify:**
- `construction-front-end/package.json` — add `@playwright/test` devDep, `"test:e2e"` script
- `construction-front-end/.gitignore` — add `playwright-report/`, `test-results/`, `playwright/.cache/`

## Implementation Steps

1. **Install Playwright:**
   ```bash
   cd construction-front-end && npm install -D @playwright/test
   npx playwright install chromium
   ```

2. **Create `playwright.config.ts`:**
   ```ts
   import { defineConfig } from "@playwright/test";

   export default defineConfig({
     testDir: "./e2e",
     fullyParallel: false,        // sequential for workflow tests
     retries: process.env.CI ? 2 : 0,
     workers: 1,
     reporter: "html",
     use: {
       baseURL: process.env.BASE_URL || "http://localhost:3000",
       trace: "on-first-retry",
       screenshot: "only-on-failure",
       locale: "en-US",
     },
     projects: [
       { name: "chromium", use: { browserName: "chromium" } },
     ],
     webServer: {
       command: "npm run dev",
       url: "http://localhost:3000",
       reuseExistingServer: true,  // don't restart if already running
       timeout: 30000,
     },
   });
   ```

3. **Create `e2e/helpers/auth-helper.ts`:**
   ```ts
   import { Page, expect } from "@playwright/test";

   const ADMIN_EMAIL = process.env.ADMIN_EMAIL || "admin@example.com";
   const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || "password123";

   export async function loginAsAdmin(page: Page): Promise<void> {
     await page.goto("/en/login");
     await page.fill("#email", ADMIN_EMAIL);
     await page.fill("#password", ADMIN_PASSWORD);
     await page.getByRole("button", { name: "Sign in" }).click();
     await page.waitForURL(/\/(en|vi)\/dashboard/);
     await expect(page).not.toHaveURL(/\/login/);
   }
   ```

4. **Update `package.json`** — add script:
   ```json
   "test:e2e": "playwright test",
   "test:e2e:ui": "playwright test --ui"
   ```

5. **Update `.gitignore`** — append:
   ```
   # Playwright
   playwright-report/
   test-results/
   playwright/.cache/
   ```

## Todo List

- [ ] Install @playwright/test + chromium browser
- [ ] Create playwright.config.ts
- [ ] Create e2e/helpers/auth-helper.ts
- [ ] Add test:e2e script to package.json
- [ ] Update .gitignore with playwright artifacts
- [ ] Verify `npx playwright test` runs (expect 0 tests found)

## Success Criteria

- `npx playwright test` executes without config errors
- Auth helper importable from test files
- Chromium browser installed and available

## Risk Assessment

- **Node version:** Playwright requires Node 18+. Project uses Node 20 LTS — OK.
- **Port conflict:** `webServer.reuseExistingServer: true` prevents conflict if dev server already running.

## Security Considerations

- Admin credentials in env vars (not hardcoded in committed tests). Defaults only for local dev.

## Next Steps

- Phase 02: Write the actual E2E test spec using this setup
