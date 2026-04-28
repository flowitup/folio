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

## 5. Project Invoices

URL: `/{locale}/projects/{projectId}/invoices`

Invoice list filtered by tabs (All / Client / Labor / Supplier) with a `+ New Invoice` button. Empty state shows "No invoices yet".

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
