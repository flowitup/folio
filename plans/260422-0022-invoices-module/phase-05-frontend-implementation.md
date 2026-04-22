---
phase: 5
title: "Frontend Implementation"
status: pending
priority: P2
effort: "2.5h"
dependencies: [4]
---

# Phase 5: Frontend Implementation

## Overview
Build the invoices UI: list page with type tabs, create form, detail/print view, and sidebar nav item. Follows existing labor page patterns (useCallback, useAuth permission check, api client). Print-to-PDF uses `window.print()` + `@media print` CSS — zero extra dependencies.

## Architecture

```
src/app/[locale]/(app)/projects/[id]/
└── invoices/
    ├── page.tsx                        # List page — tabs: All / Client / Labor / Supplier
    ├── new/
    │   └── page.tsx                    # Create form
    └── [invoiceId]/
        ├── page.tsx                    # Detail view + Edit + Print button
        └── print/
            └── page.tsx               # Print layout (no sidebar/nav chrome)

src/lib/api/
└── invoice-api.ts                     # API client functions (fetch wrappers)

src/types/
└── invoice.ts                         # TypeScript interfaces

src/components/invoices/
├── invoice-list-table.tsx             # Table component for invoice list
├── invoice-form.tsx                   # Reusable create/edit form
└── invoice-print-view.tsx             # Print-optimized invoice layout
```

## Related Code Files

- **Reference:** `construction-front-end/src/app/[locale]/(app)/projects/[id]/labor/page.tsx`
- **Reference:** `construction-front-end/src/components/layout/Sidebar.tsx`
- **Reference:** `construction-front-end/src/lib/api/http.ts`
- **Create:** `construction-front-end/src/types/invoice.ts`
- **Create:** `construction-front-end/src/lib/api/invoice-api.ts`
- **Create:** `construction-front-end/src/components/invoices/invoice-list-table.tsx`
- **Create:** `construction-front-end/src/components/invoices/invoice-form.tsx`
- **Create:** `construction-front-end/src/components/invoices/invoice-print-view.tsx`
- **Create:** `construction-front-end/src/app/[locale]/(app)/projects/[id]/invoices/page.tsx`
- **Create:** `construction-front-end/src/app/[locale]/(app)/projects/[id]/invoices/new/page.tsx`
- **Create:** `construction-front-end/src/app/[locale]/(app)/projects/[id]/invoices/[invoiceId]/page.tsx`
- **Create:** `construction-front-end/src/app/[locale]/(app)/projects/[id]/invoices/[invoiceId]/print/page.tsx`
- **Modify:** `construction-front-end/src/components/layout/Sidebar.tsx` — add Invoices nav item
- **Modify:** `construction-front-end/src/messages/en.json` — add invoice i18n keys
- **Modify:** `construction-front-end/src/messages/fr.json` — add invoice i18n keys
- **Modify:** `construction-front-end/src/messages/vi.json` — add invoice i18n keys

## Implementation Steps

1. **TypeScript interfaces** in `src/types/invoice.ts`:
   ```typescript
   export type InvoiceType = "client" | "labor" | "supplier";

   export interface InvoiceItem {
     description: string;
     quantity: number;
     unit_price: number;
     total: number;
   }

   export interface Invoice {
     id: string;
     project_id: string;
     invoice_number: string;
     type: InvoiceType;
     issue_date: string;
     recipient_name: string;
     recipient_address: string | null;
     notes: string | null;
     items: InvoiceItem[];
     total_amount: number;
     created_by: string;
     created_at: string;
     updated_at: string;
   }

   export interface CreateInvoicePayload {
     type: InvoiceType;
     issue_date: string;
     recipient_name: string;
     recipient_address?: string;
     notes?: string;
     items: Omit<InvoiceItem, "total">[];
   }
   ```

2. **API client** in `src/lib/api/invoice-api.ts`:
   ```typescript
   import { api } from "@/lib/api/http";
   import type { Invoice, CreateInvoicePayload } from "@/types/invoice";

   export const fetchInvoices = (projectId: string, type?: string) =>
     api.get<{ invoices: Invoice[]; total: number }>(
       `/projects/${projectId}/invoices${type ? `?type=${type}` : ""}`
     ).then(r => r.invoices);

   export const fetchInvoice = (invoiceId: string) =>
     api.get<Invoice>(`/invoices/${invoiceId}`);

   export const createInvoice = (projectId: string, payload: CreateInvoicePayload) =>
     api.post<Invoice, CreateInvoicePayload>(`/projects/${projectId}/invoices`, payload);

   export const updateInvoice = (invoiceId: string, payload: Partial<CreateInvoicePayload>) =>
     api.put<Invoice, Partial<CreateInvoicePayload>>(`/invoices/${invoiceId}`, payload);

   export const deleteInvoice = (invoiceId: string) =>
     api.delete<void>(`/invoices/${invoiceId}`);
   ```

3. **List page** (`invoices/page.tsx`):
   - Tab state: `"all" | "client" | "labor" | "supplier"`
   - `useCallback` to load invoices, re-fetch on tab change
   - Permission check: `canManageInvoices` from `useAuth()`
   - Table columns: Invoice #, Type badge, Date, Recipient, Total, Actions (view/delete)
   - "New Invoice" button (shown only if `canManageInvoices`)

4. **Create form** (`invoices/new/page.tsx` + `invoice-form.tsx`):
   - Fields: Type (select), Issue Date (date input), Recipient Name, Address (optional), Notes (optional)
   - Dynamic line items: add/remove rows with Description, Quantity, Unit Price, auto-computed Total per row
   - Running total displayed at bottom
   - On submit: `createInvoice()` → redirect to `/invoices/{id}`

5. **Detail page** (`invoices/[invoiceId]/page.tsx`):
   - Display all invoice fields + itemized table + grand total
   - **Print button**: `onClick={() => window.open(`/en/projects/${projectId}/invoices/${invoiceId}/print`, '_blank')}`
   - Edit mode: inline or navigate to edit form (reuse `invoice-form.tsx` with pre-filled values)
   - Delete button (with confirmation dialog) if `canManageInvoices`

6. **Print layout** (`invoices/[invoiceId]/print/page.tsx`):
   - Minimal page — no sidebar, no nav, no app chrome
   - Uses `invoice-print-view.tsx` component
   - Includes `<style>` with `@media print` rules:
     ```css
     @media print {
       @page { margin: 15mm; size: A4; }
       body { font-size: 11pt; }
       .no-print { display: none !important; }
     }
     ```
   - "Print / Save as PDF" button with class `no-print` (hidden when printing)
   - `invoice-print-view.tsx` layout: company header, invoice meta table, line items table, total row, notes

7. **Sidebar nav** in `Sidebar.tsx`:
   ```typescript
   import { Receipt } from "lucide-react";
   // In navigation array, after Labor:
   ...(selectedProjectId
     ? [{ key: "invoices", href: `/projects/${selectedProjectId}/invoices`, icon: Receipt }]
     : []),
   ```

8. **i18n keys** — add to all three locale files:
   ```json
   // navigation section
   "invoices": "Invoices",          // en
   "invoices": "Factures",          // fr
   "invoices": "Hóa đơn",           // vi

   // invoices section (new top-level key)
   "invoices": {
     "title": "Invoices",
     "newInvoice": "New Invoice",
     "invoiceNumber": "Invoice #",
     "type": "Type",
     "types": { "client": "Client", "labor": "Labor", "supplier": "Supplier" },
     "issueDate": "Issue Date",
     "recipient": "Recipient",
     "totalAmount": "Total Amount",
     "items": "Line Items",
     "description": "Description",
     "quantity": "Qty",
     "unitPrice": "Unit Price",
     "total": "Total",
     "notes": "Notes",
     "printPdf": "Print / Save PDF",
     "deleteConfirm": "Delete this invoice?"
   }
   ```

## Success Criteria

- [ ] List page shows invoices with type filter tabs, newest first
- [ ] Type badges visually distinct (different colors per type)
- [ ] Create form validates: recipient required, at least 1 item, quantity > 0
- [ ] Line item total auto-computes as quantity × unit_price on change
- [ ] Print layout hides sidebar, navbar, and action buttons via `@media print`
- [ ] Browser "Print" dialog opens on Print button click; PDF output is A4
- [ ] "Invoices" sidebar item appears only when a project is selected
- [ ] All text uses i18n translations (no hardcoded strings)
- [ ] Permission: create/edit/delete buttons hidden for users without `project:manage_invoices`

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Print layout breaks in Firefox vs Chrome | Test both; use `mm` units in `@page`, avoid flex in print CSS |
| Dynamic line items state complexity | Keep items as `useState<InvoiceItem[]>`, immutable updates via map/filter |
| Decimal precision display | Use `toFixed(2)` for display; send raw numbers to API |
