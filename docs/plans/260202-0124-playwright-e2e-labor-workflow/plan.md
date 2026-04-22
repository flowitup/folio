---
title: "Playwright E2E - Labor Charge Workflow"
description: "Setup Playwright and create E2E test for full labor charge workflow against Docker backend"
status: pending
priority: P2
effort: 1.5h
branch: feat/labor-charge-calculator
tags: [playwright, e2e, testing, labor]
created: 2026-02-02
---

# Playwright E2E - Labor Charge Workflow

Setup Playwright in construction-front-end and write an E2E test covering the full labor charge workflow against real Docker backend.

## Key Decisions

- **Test runner:** @playwright/test (new install)
- **Backend:** Real Docker (docker-compose up, seeded admin + project)
- **Navigation:** Direct URL to `/en/projects/[id]/labor` (no nav link exists yet)
- **Auth:** Login via UI form (email/password inputs, "Sign in" button)
- **Cleanup:** Test deletes its own data (entry + deactivate worker)
- **Browser:** Chromium only (speed)

## Phases

| # | Phase | Effort | Status | File |
|---|-------|--------|--------|------|
| 1 | Playwright Setup | 0.5h | pending | [phase-01](./phase-01-playwright-setup-and-configuration.md) |
| 2 | E2E Test Spec | 1h | pending | [phase-02-e2e-labor-charge-workflow-test.md](./phase-02-e2e-labor-charge-workflow-test.md) |

## Dependencies

- Labor feature fully implemented (plans/260201-2255-labor-charge-calculator — completed)
- Docker backend running with seeded admin user + test project
- Frontend dev server at http://localhost:3000

## UI Selectors Reference

| Element | Selector |
|---------|----------|
| Email input | `#email` or `getByPlaceholder("you@example.com")` |
| Password input | `#password` |
| Sign in button | `getByRole("button", { name: "Sign in" })` |
| Workers tab | `getByRole("button", { name: "Workers" })` |
| Attendance tab | `getByRole("button", { name: "Attendance" })` |
| Summary tab | `getByRole("button", { name: "Summary" })` |
| Add Worker button | `getByRole("button", { name: "Add Worker" })` |
| Log Attendance button | `getByRole("button", { name: "Log Attendance" })` |
| Save button | `getByRole("button", { name: "Save" })` |
| Delete button | `getByRole("button", { name: "Delete" })` |
| Deactivate button | `getByRole("button", { name: "Deactivate" })` |

## Brainstorm Report

- [Brainstorm](../../plans/260201-2255-labor-charge-calculator/reports/brainstorm-260202-0112-playwright-e2e-labor-workflow.md)
