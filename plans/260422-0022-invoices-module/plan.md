---
title: "Invoices (Factures) Module"
description: "Per-project invoice management (client/labor/supplier) with browser print-to-PDF and RBAC enforcement"
status: completed
priority: P2
effort: "8h"
created: 2026-04-22
completed: 2026-04-22
branch: feat/invoices-module
tags: [invoices, factures, backend, frontend, pdf, rbac]
---

# Invoices (Factures) Module

Full invoicing module for the construction management app. Invoices are per-project documents with three types (client / labor / supplier), manual line items stored as JSONB, and browser-native print-to-PDF. No payment tracking — invoices are documents only.

## Key Decisions

- **JSONB items** — avoids InvoiceItem join table; no need to query individual items (YAGNI)
- **Browser print-to-PDF** — zero backend PDF lib; `@media print` CSS hides app chrome
- **`project:manage_invoices` permission** — new RBAC permission following existing pattern
- **Auto invoice number** — format `INV-YYYY-NNNN` generated at creation (sequential per project)
- **Follows labor module pattern** exactly: same hexagonal layer structure, same API conventions

## Phases

| # | Phase | Effort | Status | File |
|---|-------|--------|--------|------|
| 1 | Database & Domain Layer | 1h | Completed | [phase-01](./phase-01-database-domain-layer.md) |
| 2 | Application Layer (Use Cases) | 1.5h | Completed | [phase-02](./phase-02-application-layer-use-cases.md) |
| 3 | Infrastructure Adapters | 1h | Completed | [phase-03](./phase-03-infrastructure-adapters.md) |
| 4 | API Endpoints | 1.5h | Completed | [phase-04](./phase-04-api-endpoints.md) |
| 5 | Frontend Implementation | 2.5h | Completed | [phase-05](./phase-05-frontend-implementation.md) |
| 6 | Testing | 0.5h | Completed | [phase-06](./phase-06-testing.md) |

## Dependencies

- Completed: `plans/260201-2255-labor-charge-calculator` (same hexagonal patterns used)
- Existing `projects` table with UUID PK
- RBAC permission system (JWT claims, `require_permission` decorator)
- Next.js 16 App Router, next-intl i18n, Shadcn UI
