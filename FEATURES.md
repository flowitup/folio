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

Invoice list filtered by tabs (All / Client / Labor / Supplier) with a `+ New Invoice` button. Empty state shows "No invoices yet".

Screenshot: `screenshots/invoices-list.jpg`

## 5b. Invoices · Monthly export (Excel / PDF)

URL: `GET /api/v1/projects/{projectId}/invoices-export?from=YYYY-MM&to=YYYY-MM&format=xlsx|pdf[&type=client|labor|supplier]`

UI: an `Export range` button on the invoices page header opens a dialog asking for `from` / `to` months, optional type filter (All / Client / Labor / Supplier), and xlsx/pdf format. Range capped at 24 months. The active list-tab type carries through as the dialog's initial type filter.

Output:
- **xlsx** — `Summary` sheet (project header, KPI block, per-type subtotals, full invoice list with `# · Date · Type · Recipient · Items · Total`, GRAND TOTAL band) + one sheet per type that exists in the range (skips empty types). Currency cells store raw float values with `EUR_FR_FORMAT` so Excel can sort and sum them.
- **pdf** — A4 portrait. Page 1: project-header band + meta line (range / generated-at / generated-by) + KPI strip + Subtotals-by-type table + Invoices index table. Pages 2..N+1: ONE polished invoice per page (project-header band + INVOICE title + meta block + line-items table with zebra rows + grand-total band + notes section if non-empty). Page footer `Generated by … · Page X` on every page.

Empty range path renders a clean `No invoices in range YYYY-MM to YYYY-MM` paragraph in both formats — no crash, no garbage cells.

Filename pattern: `invoices-{project-slug}-{from}-to-{to}[-{type}].{ext}` — type suffix only when the filter is set; slugifier reused from labor (`slugify_project_name`, falls back to first 8 chars of UUID for pure CJK / emoji names).

Security:
- `@jwt_required + @require_permission("project:read") + @require_project_access()` — caller must be a member of the specific project.
- Per-user rate limit (5/min, `key_func=jwt_user_key`) — separate bucket per user, not per IP.
- ReportLab `Paragraph` user-input is XML-escaped (`xml.sax.saxutils.escape`) for project name, recipient name/address, invoice number, item descriptions, and notes.
- `Cache-Control: no-store, must-revalidate` + `X-Content-Type-Options: nosniff` on the response — no proxy caching of the binary, no MIME sniffing.
- Subtotals + grand total aggregated in `Decimal`; `float()` cast only at xlsx-cell-write boundary (no float drift on summed currency).

Currency formatting: fr-FR throughout (`1 234,56 €`) — matches FE `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })`.

i18n: `invoices.export.*` keys at strict en/fr/vi parity (20 keys, real Vietnamese translation including "Khách hàng" / "Nhân công" / "Nhà cung cấp" for the type filter).

Tightened in this cycle (also back-ported to labor): `^(19|20|21)\d{2}-(0[1-9]|1[0-2])$` regex on YYYY-MM (no more `0000-01` → 500), explicit `elif` / `else: raise` on the format dispatch (no silent PDF fallthrough), and one canonical `format_validation_error(exc)` helper at `app/api/_helpers/pydantic_errors.py` shared by invoice + both labor export routes.

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

## 9. Settings

URL: `/{locale}/settings`

Application settings page split into three sections — Profile Settings, Notification Preferences, Organization Settings — each marked "will be available soon", indicating placeholders for future work.

Screenshot: `screenshots/settings.jpg`

## 10. Unauthorized (403)

URL: `/{locale}/unauthorized`

Permission-denied page rendered by the auth middleware when a user lacks the required permission. Big "403", explanatory text, and a `Go to Dashboard` button.

Screenshot: `screenshots/unauthorized.jpg`

---

## Cross-cutting features visible in every authenticated page

These aren't standalone routes but are present in the chrome of every screenshot above:

- Sidebar navigation — Overview / Projects / Labor / Invoices / Settings; Labor and Invoices only appear once a project is selected.
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
| Unauthorized | `/sessions/nice-eloquent-thompson/mnt/outputs/screenshot-1777111464704.jpg` |

To get them into the requested folder you can either drag them out of the attachments and drop them into `~/Works/construction/.feature-screenshots/` with the names referenced above (`login.jpg`, `dashboard.jpg`, etc.), or re-run the screenshot pass with the Chrome-MCP outputs folder mounted into this session.
