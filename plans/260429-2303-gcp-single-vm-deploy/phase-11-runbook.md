---
phase: 11
title: "Runbook"
status: pending
priority: P2
effort: "2h"
dependencies: [9, 10]
---

# Phase 11: Runbook

> **[REVISED 2026-04-29]** **YAGNI Y6:** doc surfaces trimmed 5 → 2. Only `docs/deployment-guide.md` (full runbook, ≤ 800 lines, TOC serves as quick-ref) + 1 milestone line in `docs/project-roadmap.md`. `runbook-quick-reference.md` + `system-architecture.md` + `codebase-summary.md` updates DELETED from scope. **The `## Validation Decisions` section at the end is authoritative**; supersedes the original Related Code Files list.

## Overview

Update `docs/deployment-guide.md` to be the single source of operational truth: deploy, rollback, restore, scale, rotate secrets, debug. Written so a new operator can resolve a Sev-1 alone at 3 AM.

## Requirements

- **Functional:** Each scenario (deploy / rollback / restore / scale / rotate / debug) has a copy-pasteable command sequence + expected outputs + escalation contact.
- **Non-functional:** Scannable structure (TOC + clear headings); kept under 800 lines per `docs.maxLoc`; cross-linked to plan phases for context.

## Architecture

```
docs/deployment-guide.md
├── TOC
├── 1. Architecture (1-screen overview + diagram)
├── 2. Common operations
│   ├── Deploy (push to main flow)
│   ├── Rollback (manual workflow_dispatch)
│   ├── Connect (gcloud ssh via IAP)
│   └── Read logs (Cloud Logging filter cheatsheet)
├── 3. Incidents
│   ├── Site down — first 5 minutes
│   ├── Database recovery (point-in-time)
│   ├── MinIO data recovery
│   ├── VM lost (full rebuild from snapshot)
│   └── Cloudflare outage workaround
├── 4. Maintenance
│   ├── Rotate secrets
│   ├── Renew SSH keys
│   ├── Scale VM up/down
│   ├── Quarterly restore drill
│   └── Cost review
└── 5. Escalation contacts
```

## Related Code Files

- Update: `docs/deployment-guide.md` — main runbook.
- Update: `docs/system-architecture.md` — add deploy section.
- Update: `docs/project-roadmap.md` — mark deploy milestone.
- Update: `docs/codebase-summary.md` — note infra dirs.
- Create: `docs/runbook-quick-reference.md` — 1-page cheatsheet (printable).

## Implementation Steps

1. Outline the runbook headings; confirm each maps to a scenario tested in phases 9–10.
2. For each "Common operation" copy the exact command sequence used in CI / drill, with sample output snippets so operator knows what "good" looks like.
3. For each "Incident" write a tree:
   - Symptom checklist
   - Diagnostic queries (specific Cloud Logging links)
   - Decision tree (rollback vs hotfix vs restore)
   - Recovery commands
   - Post-incident: write journal entry, update this runbook.
4. Cross-link from each section to the relevant plan phase file (so context isn't lost).
5. Add ASCII architecture diagram (matches plan.md).
6. Print + post the quick-reference page where operator can grab it.
7. Tabletop walk-through: read runbook aloud while imagining each scenario. Tighten ambiguous steps.
8. Mark runbook reviewed in `docs/project-roadmap.md`.

## Success Criteria

- [ ] `docs/deployment-guide.md` covers all 5 sections, ≤ 800 lines.
- [ ] Every "incident" scenario has been tested at least once (phase 10 covers some; rest via tabletop).
- [ ] New developer can deploy a code change end-to-end using only the runbook (no Slack hint).
- [ ] Quick-reference page exists, fits on 1 page printed.
- [ ] Cross-links to plan phases work.
- [ ] `docs/system-architecture.md` reflects the deployed reality.
- [ ] Reviewed by user before marking phase complete.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| Runbook drifts from reality | Each phase deploy/change requires a runbook PR; CI lint warns if `docs/deployment-guide.md` not touched in deploy-affecting PRs. |
| Runbook too long to be useful at 3 AM | Quick-reference page is the always-print page; long form for context. |
| Operator follows runbook blindly through wrong path | Decision trees explicit ("if X, go to §3.2; if Y, §3.3"); avoid linear narratives. |
| Out-of-date secrets rotation steps fail mid-incident | Rotation tested as part of phase 6; runbook references rotation script, not raw commands. |
| New operator never reads it | Onboarding checklist requires runbook read + tabletop walk-through. |

## Validation Decisions (2026-04-29 Session 1)

**Y6 — Reduce doc surfaces 5 → 2.**

Original plan touched 5 doc files: `deployment-guide.md` + `system-architecture.md` + `project-roadmap.md` + `codebase-summary.md` + new `runbook-quick-reference.md`. **Trimmed to 2.**

**Kept:**
- ✅ `docs/deployment-guide.md` — the runbook itself. Replaces the existing "blueprint" content. ≤ 800 lines per `docs.maxLoc`. TOC at top serves as the quick-reference (no separate file needed).
- ✅ `docs/project-roadmap.md` — **one milestone-tick line** added (e.g. "✅ 2026-05-XX: Production deploy live (Option A, GCP)").

**Dropped:**
- ❌ `docs/system-architecture.md` update — current architecture-summary doc remains a planning artifact; deploy specifics live in `deployment-guide.md`.
- ❌ `docs/codebase-summary.md` update — infra dirs (`infra/gcp/`, `scripts/deploy/`, `scripts/backup/`) are self-documenting via kebab-case naming; no narrative needed.
- ❌ `docs/runbook-quick-reference.md` (new file) — the deployment-guide TOC + first "Common operations" section IS the quick reference.

### Updated Success Criteria (replacements)

- [ ] `docs/deployment-guide.md` covers all 5 sections (TOC, Common ops, Incidents, Maintenance, Escalation) in ≤ 800 lines. The TOC + Common ops section serves as the always-visible quick reference.
- [ ] One milestone line added to `docs/project-roadmap.md`.
- [ ] **Removed:** updates to `system-architecture.md`, `codebase-summary.md`, and the new `runbook-quick-reference.md`.

**Effort reclaimed:** ~1h (1 file to update + 1 line to add, vs 4 files + 1 new file).
