# Brainstorm: Invoices (Factures) Module

**Date:** 2026-04-22 | **Project:** Construction Management App

---

## Problem Statement

Add an invoicing section to the construction management app. The app currently handles projects, labor tracking, and user management. Missing: a way to create and manage financial documents (invoices) per project.

## Requirements (confirmed)

| Item | Decision |
|------|----------|
| Invoice types | Client + Labor + Supplier (all three) |
| PDF output | Browser print-to-PDF (window.print + @media print CSS) |
| Payment tracking | None — invoices are documents only |
| Labor auto-import | No — manual line items only |
| Scope | Per-project invoices, linked to existing project context |

## Evaluated Approaches

### PDF Generation

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| Browser print-to-PDF | Zero deps, works in Docker, user controls PDF quality | User must click print | ✅ Chosen |
| fpdf2 (server-side) | Pure Python, no system libs | Basic styling, more code | Rejected (over-engineered) |
| WeasyPrint | Beautiful output | +200MB Docker image, libcairo/pango deps | Rejected (YAGNI) |

### Items Storage

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| JSONB column | Simple, no join, flexible schema | Can't query individual items | ✅ Chosen (YAGNI — no item-level queries needed) |
| InvoiceItem table | Queryable, normalized | Extra join, migration complexity | Rejected |

---

## Final Recommended Solution

### Data Model

```
invoices table
├── id           UUID PK
├── project_id   FK → projects
├── invoice_number  VARCHAR (auto: INV-YYYY-NNNN)
├── type         ENUM('client', 'labor', 'supplier')
├── issue_date   DATE
├── recipient_name    VARCHAR
├── recipient_address TEXT (nullable)
├── notes        TEXT (nullable)
├── items        JSONB  [{description, quantity, unit_price, total}]
├── created_by   FK → users
├── created_at   TIMESTAMP
└── updated_at   TIMESTAMP
```

### Backend Architecture (hexagonal — same pattern as Labor)

```
domain/invoice/
  invoice.py, invoice_repository.py

application/invoice/
  create_invoice.py, list_invoices.py, get_invoice.py,
  update_invoice.py, delete_invoice.py

infrastructure/persistence/
  invoice_model.py, invoice_repository_impl.py

api/v1/invoices/
  namespace.py

migrations/
  xxxx_add_invoices_table.py
```

**Endpoints:**
- `GET    /api/v1/projects/{id}/invoices`
- `POST   /api/v1/projects/{id}/invoices`
- `GET    /api/v1/invoices/{invoice_id}`
- `PUT    /api/v1/invoices/{invoice_id}`
- `DELETE /api/v1/invoices/{invoice_id}`

**New permission:** `project:manage_invoices` (added to manager + admin roles)

### Frontend Architecture (Next.js App Router)

```
(app)/projects/[id]/
  invoices/           → list page with type tabs
  invoices/new/       → create form (type + line items)
  invoices/[invoiceId]/        → detail view
  invoices/[invoiceId]/print/  → print layout (no sidebar/nav)
```

- Sidebar: "Invoices" nav item (same conditional pattern as Labor)
- Print button: `window.print()` on dedicated print layout
- i18n: add invoice keys to en/fr/vi messages

---

## Implementation Risks

| Risk | Mitigation |
|------|------------|
| Invoice number collision (concurrent creates) | DB sequence or advisory lock |
| JSONB schema drift | Pydantic validation on write |
| Print layout differs by browser | Test Chrome + Firefox, use fixed units (mm) in @media print |

## Success Criteria

- [ ] CRUD invoices per project (all 3 types)
- [ ] Invoice list filterable by type
- [ ] Print view renders correctly + hides app chrome
- [ ] Browser PDF matches expected layout
- [ ] Permission `project:manage_invoices` enforced
- [ ] All existing tests still pass
