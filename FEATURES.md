# Construction App — Feature Catalog

A walkthrough of the user-facing features in the Construction Management System. The app is a Next.js (App Router, i18n) front-end backed by a Flask + Postgres API, deployed via `docker compose`.

App: http://localhost:3000  •  API: http://localhost:5000  •  Auth: JWT (cookie-based with CSRF for browsers)

---

## 1. Login

URL: `/{locale}/login` — e.g. `http://localhost:3000/en/login`

Email + password sign-in form. Blank state shown before login; on bad credentials an inline "Invalid email or password" alert appears below the heading. After success, the user is redirected to the Dashboard.

Screenshot: `screenshots/login.jpg`

## 2. Dashboard (Overview)

URL: `/{locale}/dashboard`

Authenticated landing page. Top bar holds a project selector, language switcher (EN/VI/FR), dark-mode toggle, notifications bell and user menu. The body shows three KPI cards (Active Projects, Pending Tasks, Team Members — all "Awaiting data" until populated) and a "Recent Activity" panel.

Screenshot: `screenshots/dashboard.jpg`

## 3. Projects list

URL: `/{locale}/projects`

Grid of project cards (Downtown Office Tower, Shopping Mall Renovation, Riverside Apartments in the seeded data). Each card shows name, address, member count and an action menu; the currently active project is highlighted with a "Selected" badge. A `+ New Project` button sits in the page header.

Each card's kebab opens a `DropdownMenu` with **Edit project** (opens a Dialog pre-filled with name + address — no-op when unchanged), **Delete project** (opens an AlertDialog with cascade copy: workers / labor entries / tasks / expenses / notes / invitations / memberships permanently deleted; quotes + invoices unlinked but kept — gated by typed-name confirmation), and **Show / Hide team**. Edit + Delete only render for the project owner or an admin (`project:create` / `project:*` / `*:*`).

Screenshot: `screenshots/projects.jpg`

## 4. Project Labor

URL: `/{locale}/projects/{projectId}/labor`

"Labor Charges" workspace scoped to the active project, with three tabs:

- Workers — list of workers with daily rate and phone, plus per-row edit / assign actions and an `+ Add Worker` button.
- Attendance — log attendance for workers on a given day.
- Summary — aggregated labor cost summary.

The screenshot captures the Workers tab populated with the seeded crew (Jean Dupont, Lucas Dubois, Marie Bernard, Pierre Martin, Sophie Moreau).

Screenshot: `screenshots/labor.jpg`

## 4b. Labor · Supplement hours

URL: `/{locale}/projects/{projectId}/labor` (Attendance tab)

Workers can accrue banked supplement hours (0–12 per day) alongside or instead of a shift. Across the calendar month the hours accumulate; every 8h converts to 1 bonus full-day, every 4h remainder to 1 bonus half-day. The Summary tab reflects per-worker `banked_hours`, `bonus_full_days`, `bonus_half_days`, and `bonus_cost` alongside the existing totals. Supplement-only entries (no shift type) are supported — useful for partial-day or on-call situations where the worker has no formal shift code.

Conversion is entirely derived at read time — no background job, no monthly close action. Residual hours under 4 at month boundary are discarded with no carry-over.

## 4c. Labor · Export (Excel / PDF)

URL: `GET /api/v1/projects/{projectId}/labor-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf`

Exports labor data for a project over a 1-to-24-month window. Two formats:

- **xlsx** — one sheet per month (daily attendance detail + per-worker totals) plus a Summary sheet aggregating priced and bonus costs across the range. Uses fr-FR number format (`[$€-fr-FR]`) for currency cells.
- **pdf** — A4 portrait; KPI mini-table at the top followed by a per-worker monthly breakdown. Uses bundled DejaVu Sans fonts so Vietnamese diacritics render correctly.

Both formats display "Priced cost" and "Bonus cost" as separate columns — no single aggregated "Total" that could obscure the split. Any combined figure is explicitly labeled "Total (priced + bonus)".

The filename is slugified from the project name and the requested date range (e.g. `downtown-office-2026-01-2026-03.xlsx`). The response streams directly as an attachment (`Content-Disposition: attachment`); no temporary file is written to disk.

Authentication: JWT cookie or Bearer token, `project:read` permission required.

## 4d. Labor · Single-worker export

URL: `GET /api/v1/projects/{projectId}/workers/{workerId}/labor-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf`

UI: a Download icon on each active worker row of the labor page (`/{locale}/projects/{projectId}/labor`) opens an export dialog scoped to that single worker. Title shows the worker name, subtitle shows their daily rate; the same from/to/format inputs as the project-wide dialog drive the request.

Output:
- **xlsx** — one sheet (sanitized worker name as title) with header (project, worker, rate, range, generated-at), monthly summary table for the worker, and daily detail table sorted by date.
- **pdf** — A4 portrait, header includes a `Worker: {name}    Rate: {rate}/day` line, KPI mini-table + breakdown of the worker's totals; no daily detail (parity with the project-wide PDF).

Filename pattern: `labor-{project-slug}-{worker-slug}-{from}-to-{to}.{ext}` — slugifier falls back to the first 8 chars of the UUID when the name is pure CJK or emoji.

Security:
- `@jwt_required + @require_permission("project:read") + @require_project_access()` — caller must be a member of the specific project, not just hold the `project:read` claim.
- Per-user rate limit (5/min, `key_func=jwt_user_key`) — separate bucket per user, not per IP.
- ReportLab `Paragraph` user-input is XML-escaped to prevent crashes on `<` and prevent markup injection.
- Inactive worker → 404 `worker_inactive` (the FE button is already gated on `is_active`; this is defense-in-depth).
- Cross-project worker → 404 `worker_not_found`.

## 5. Project Invoices

URL: `/{locale}/projects/{projectId}/invoices`

Invoice list filtered by tabs (All / Client / Labor / Supplier) with a `+ New Invoice` button. Columns: Invoice #, Type, Issue date, Recipient, **Payment method** (stamp/tag from the per-invoice snapshot; built-in "Cash" localised per locale; em-dash when blank), Total, Actions. Empty state shows "No invoices yet".

Screenshot: `screenshots/invoices-list.jpg`

## 6. New Invoice

URL: `/{locale}/projects/{projectId}/invoices/new`

Invoice creation form with Type (Client / Labor / Supplier), Issue Date, Recipient, Address, Notes, and a Line Items table (Description, Qty, Unit Price, Total) with `+ Add Item`. A live total is shown above the Save button.

Screenshot: `screenshots/invoice-new.jpg`

## 7. Invoice detail

URL: `/{locale}/projects/{projectId}/invoices/{invoiceId}`

Detail view for a single invoice (rendered after picking one from the list). In this snapshot the page is in its `Failed to load invoice` error state — the invoice POST returned `201` but immediately afterwards `GET /invoices/{id}` returned `404`, so the page can't hydrate. Worth flagging as a bug; the route, layout and error UI are still visible.

There is also a print-only sibling route at `/{locale}/projects/{projectId}/invoices/{invoiceId}/print`.

Screenshot: `screenshots/invoice-detail.jpg`

## 7b. Project Members (admin)

URL: `/{locale}/projects/{projectId}/members`

Admin workspace for managing project membership. Two tables side-by-side: **Members** (avatar/name, email, role, joined date) and **Pending invitations** (email, role, expires-in, invited by, Revoke action). Top-right `Invite member` button opens a dialog with email + role select; on submit the invitee receives an email with a 7-day single-use link. If the email already belongs to a user, the system bypasses the email link and adds them directly with a "you've been added" notification. Only project owners or users with the global `admin` role see the Invite button. Rate-limited to 10 invites/hour per inviter and 50/day per project to protect Resend free-tier quota.

## 7c. Accept invitation (public)

URL: `/{locale}/accept-invite/{token}`

Public landing page for invitees clicking the email link. Server-side verifies the token and renders one of four states: (a) **valid** → "You're invited to join {Project} as {Role}" banner over a name + password + confirm form; on submit the account is created, JWT cookies set, and the user lands on the dashboard authenticated. (b) **expired / revoked / accepted** → clear error message with a "Go to login" CTA. (c) **invalid token** → generic "this invitation link is invalid". (d) **logged in as someone else** → sign-out gate (no info leak about the invite target). Self-serve signup remains disabled — invitations are the only path to an account.

## 7d. Superadmin · Bulk add user to multiple projects

URL: `/{locale}/admin/users`

Superadmin-only page (visible to users with global `admin` role / `*:*` permission). Three-step form: debounced user search (≥3 chars, picks an existing user by email or display name), multi-select projects (with client-side filter, capped at 50 per request), single role applied across all selected projects. On submit the system attempts to add the user to each selected project; results come back as a per-project status array (`added` / `already_member_same_role` / `already_member_different_role` / `project_not_found`) and the UI surfaces them as grouped toasts. If any project was newly added, the target user receives one consolidated email listing all newly-added projects + the role. Refuses silent role overrides — admins must use a future role-change endpoint for that. Rate-limited to 5 bulk ops/hour per superadmin + 10/hour per IP.

## 7e. Settings → Users & Roles tab

URL: `/{locale}/settings` (Users section, 7th tab)

Bulk-assign roles to existing users across one or more projects. Permission-gated: superadmin (`*:*`) sees the three-step bulk-add form (user search, project multi-select, role picker); non-superadmin sees an inline "you don't have authorization" panel rendered in the section content area — no redirect to `/unauthorized`. Replaces the old `/{locale}/admin/users` standalone route, which is deleted. Sidebar ADMIN nav section removed.

## 8. Notes (per-project shared, with in-app reminders)

Members of a project can capture notes with a due date and a lead time. When the lead time expires before the due date, the note appears as a reminder in the topbar bell-icon dropdown for **all** members of the project. Each member can dismiss reminders independently.

**Capabilities**
- Create / edit / delete notes (any project member)
- Mark notes done / open
- Inline-edit rows on the agenda page (`/projects/:id/notes`)
- Agenda groups: Today / Tomorrow / This week / Later / Done
- 3 lead-time presets: at due time / 1 hour before / 1 day before
- Bell-icon dropdown polls every 60s; per-row dismiss
- Reminders fire at **09:00 UTC** of the due date (per-user timezone deferred to v2)

**Out of scope (v1)**
- Email reminders (deferred — pipeline ready for v2)
- Recurrence
- Browser push notifications
- Per-note assignees
- Per-user timezone column

## 8b. Project Documents (per-project file storage)

URL: `/{locale}/projects/:id/documents`

Sidebar entry "Documents" appears after Notes when a project is selected. Project members upload, list, preview, download, and soft-delete files attached to the project (plans, contracts, photos, invoice receipts, etc.). Stored on the existing MinIO bucket via the `project-documents/` key prefix.

**Capabilities**
- Drag-and-drop upload zone + `Pick files` button — multi-file via N parallel `XMLHttpRequest` POSTs with per-file progress bar (XHR `upload.onprogress`)
- File-type allowlist: PDF, PNG / JPG / WebP, DOCX, XLSX, DWG, TXT — 25 MB cap per file (env `PROJECT_DOCUMENT_MAX_SIZE_BYTES`)
- Table with sortable columns: File name, Type, Size, Uploaded by, Uploaded date — pagination (page size 25, max 100)
- Filter chips for type (All / PDF / Image / Spreadsheet / Document / CAD / Text / Other) + uploader `<Select>`
- Inline preview dialog: `<embed>` for PDF, `<img>` for images, fallback "Download to view" for other types. Authenticated via blob-fetch with Bearer JWT (native `<embed src>` can't send headers).
- Per-row download button (also authenticated via blob-fetch + transient `<a>` click).
- Soft-delete with confirm dialog — uploader OR project owner OR `*:*` admin only.
- Rate-limited: 30 uploads / minute / user (Flask-Limiter, keyed by JWT identity).

**Out of scope (v1, tracked as follow-ups)**
- OCR / full-text search
- Virus / malware scan
- Server-side preview-conversion (DOCX / XLSX / DWG → PDF preview)
- Bulk-zip download
- Versioning / replace-in-place
- MinIO janitor for soft-deleted rows (objects retained indefinitely)
- UI to recover soft-deleted documents

## 9. Settings

URL: `/{locale}/settings`

Application settings page split into sections — Profile Settings, Notification Preferences, Organization Settings, and Company Profile (see #11 below). Sections not yet implemented show "will be available soon" placeholders.

Screenshot: `screenshots/settings.jpg`

## 10. Unauthorized (403)

URL: `/{locale}/unauthorized`

Permission-denied page rendered by the auth middleware when a user lacks the required permission. Big "403", explanatory text, and a `Go to Dashboard` button.

Screenshot: `screenshots/unauthorized.jpg`

## 11. Billing (Devis / Factures / Templates)

URLs: `/{locale}/billing/devis`, `/{locale}/billing/factures`, `/{locale}/billing/templates`

Outgoing client-facing pricing proposals and invoices, with per-document PDF export, status lifecycle (`draft → sent → accepted/rejected/expired` for devis; `draft → sent → paid/overdue/cancelled` for factures), atomic per-(company, kind, year) document numbering (`DEV-YYYY-NNN` / `FAC-YYYY-NNN`), and user-managed template skeletons for fast doc creation. Issuer info sourced from the selected company; snapshotted onto each doc at create time so historical documents are immutable.

**Sub-routes:**
- `/billing/devis` — list + filter by status; `+ New Devis` CTA; empty state.
- `/billing/devis/new` — blank form, "from existing" picker, or "apply template" picker; company picker at top.
- `/billing/devis/[id]` — edit form with live HT/TVA/TTC totals, status transition menu, Download PDF, and "Convert to Facture" action (accepted devis only).
- `/billing/factures` — same shape as devis list, facture-specific statuses.
- `/billing/factures/new` — same three creation modes.
- `/billing/factures/[id]` — edit + status menu + Download PDF; no convert action.
- `/billing/templates` — list by kind; create / edit / delete skeletons.
- `/settings` → Companies section — manage attached companies; admin manages all companies + invite tokens.

**Key behaviors:**
- Items table: Description / Qty / Unit price HT / VAT% / Total HT; per-rate TVA breakdown + grand total TTC computed live.
- PDF rendered server-side via ReportLab (DejaVu fonts, Vietnamese-safe); downloaded via browser, not emailed.
- Convert devis → facture: clones the row as a new facture (new number, `status=draft`), links `source_devis_id`; guarded against double-convert by a unique constraint.
- Mixed VAT rates per document supported (French construction standard).
- All routes `@jwt_required()`; user owns their own documents (no project-membership check unless `project_id` is set on the doc).

**Out of scope (v1):** bulk export, email-as-attachment, separate clients directory, multi-currency, attachments, e-signature.

### Activity suggestions + line-item categories (added phase 260510-2225)

- Each line item now carries an optional `category` (e.g. *Toiture*, *Menuiserie*, *Plomberie*) — stored inside the existing JSONB items blob; no DB migration.
- New "Section" column in the items editor (left of description). Both columns are typeahead Comboboxes (`cmdk`-based shadcn primitive, debounced 200ms). Description suggestions auto-fill unit / unit price / VAT rate from the most recent past use; free-text on Enter/blur creates a new value.
- `GET /api/v1/billing-documents/activity-suggestions` returns the requester's distinct (category, description) pairs ranked by frequency, with `last_*` hints. User-scoped; never leaks across users.

### Historical document import

- `POST /api/v1/billing-documents/import` accepts a verbatim `document_number`, explicit `status`, and optional `created_at`, bypassing auto-numbering for legacy ingestion. Counter is bumped to `MAX(existing, parsed_seq)` so future user-created docs continue from the right point.
- One-shot script `folio-back-end/scripts/import_legacy_factures.py` parses xlsx + PDF source files into the import payload. Idempotent on duplicate document numbers (HTTP 409 → skip).

## 12. Multi-company profiles

Admin-managed shared companies (legal entities) attached to user accounts via 7-day single-use invite tokens. Replaces the former 1:1 `company_profile` model; existing profiles auto-migrate with no user action required.

**Key behaviors:**
- Admin creates a company, generates an invite token (plaintext shown once, argon2-hashed in DB); user pastes the token in Settings → a `user_company_access` row is created with `is_primary=true` on first attachment.
- Per-company numbering: `billing_number_counters` re-keyed to `(company_id, kind, year)`; `billing_documents` unique on `(company_id, kind, document_number)` so each legal entity has an independent continuous sequence.
- Sensitive fields (`siret`, `tva_number`, `iban`, `bic`) masked in UI for non-admins (`····5678`); full values always rendered on PDFs (legal requirement) via the existing issuer-snapshot columns.
- Doc create form gains `<CompanyPickerSelect>`: auto-uses if user has exactly 1 company; dropdown with primary/last-used (localStorage `billing.lastCompanyId.${kind}`) defaults for 2+.
- Admin boot (remove a user from a company) returns 409 `company_no_longer_attached` if the user attempts to save a doc from that company mid-flow.

**Endpoints:** 12 (see `docs/checklist/feature-checklist.md` → Companies section)
**New tables:** `companies`, `user_company_access`, `company_invite_tokens`
**Modified tables:** `billing_documents` (+ `company_id`), `billing_number_counters` (re-keyed PK)
**Dropped table:** `company_profile`

## 13. Invoice payment method (per-company list with snapshot label)

URLs: `/{locale}/settings/companies/{id}` (Payment Methods card) + `/{locale}/projects/{projectId}/invoices/new` (Payment method dropdown on the invoice form).

Each company carries a CRUD-able list of payment methods used when recording invoices. On company create, two builtins are seeded: `Cash` and the company `legal_name` (e.g. `Folio Test SARL`). Members can add their own (Wise, Stripe, bank account labels, …); built-ins can be **renamed** but not **deleted/deactivated** (badge: `Built-in`).

Invoices reference a method by id but **also persist the label as a snapshot** at write time. Renaming a method later does not change the historical invoice's label — the snapshot survives soft-delete and rename, providing audit safety.

**Key behaviors:**
- List read = any company member (404 on cross-tenant requests; no info leak).
- Create / rename / soft-delete = global `*:*` admin (mirrors existing CompanyUseCases pattern).
- Soft-delete preserves the `payment_methods` row; partial unique index allows re-creating a same-label method afterward.
- Invoice edit accepts `payment_method_id: null` to clear; detail row shows `—` when cleared.
- FE Settings card supports inline-add, edit-in-place, delete-confirm dialog (with `usage_count` badge to warn when methods are referenced).
- Invoice form uses a `PaymentMethodSelect` combobox with inline-create — typing a new label and pressing Enter POSTs and selects the result without leaving the form.
- i18n parity across en/fr/vi for `paymentMethods.*` and `invoices.paymentMethod.*` (35 keys × 3 locales).

**Endpoints:** 4 (see `docs/checklist/feature-checklist.md` → Payment Methods section)
**New tables:** `payment_methods`
**Modified tables:** `invoices` (+ `payment_method_id`, `payment_method_label`)
**Migration:** `cea9f050672d_add_payment_methods_and_invoice_columns` — backfills `Cash` + `TRIM(legal_name)` builtins for every existing company; reversible.

---

## Cross-cutting features visible in every authenticated page

These aren't standalone routes but are present in the chrome of every screenshot above:

- Sidebar navigation — Overview / Projects / Labor / Invoices / **Billing** / Settings; Labor and Invoices only appear once a project is selected; Billing is a top-level group (always visible) with three sub-entries (Devis / Factures / Templates) that expand on click and persist state in localStorage.
- Project selector in the top bar — switches the active project for the Labor and Invoices sections.
- Locale switcher — three languages (English, Tiếng Việt, Français).
- Dark-mode toggle.
- User menu with `Sign out`.

---

## Screenshot paths

The screenshots were saved by the Chrome-MCP server into its own sandbox. They are user-attachable from those paths, but the Chrome-MCP sandbox is isolated from this session's `/Users/sweet-home/Works/construction/` mount, so they could not be written directly into `/Users/sweet-home/Works/construction/.feature-screenshots/`.

| Feature | Path |
|---|---|
| Login | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111227374.jpg` |
| Dashboard | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111266623.jpg` |
| Projects list | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111284979.jpg` |
| Project Labor | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111310851.jpg` |
| Project Invoices | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111322115.jpg` |
| New Invoice | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111334718.jpg` |
| Invoice detail | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111374071.jpg` |
| Settings | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111456252.jpg` |
| Unauthorized | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111464504.jpg` |
