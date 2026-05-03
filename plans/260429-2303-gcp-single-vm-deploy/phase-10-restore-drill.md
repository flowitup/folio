---
phase: 10
title: "Restore Drill"
status: pending
priority: P2
effort: "4h"
dependencies: [7, 9]
---

# Phase 10: Restore Drill

> **[REVISED 2026-04-29]** WAL replay step removed (phase 7 no longer ships WAL). Migration command fixed (`FLASK_APP=wsgi:app`). RPO target ≤ 24 h, not ≤ 5 min. **YAGNI Y4:** quarterly drill auto-trigger DELETED (no Cloud Scheduler, no Cloud Function, no janitor cron). Manual `run-drill.sh` + calendar reminder is the cadence. **The `## Red Team Fixes` and `## Validation Decisions` sections at the end are authoritative**.

## Overview

Validate the backup story end-to-end by destroying state on a sidecar VM and restoring from GCS. Without this drill, backups are theoretical. Goal: prove RTO ≤ 30 min, RPO ≤ 5 min for DB.

## Requirements

- **Functional:** Wipe a clone VM's data → restore Postgres + MinIO + WAL → app boots and serves identical data to prod.
- **Non-functional:** Drill scripted so it can re-run quarterly with one command. Production untouched.

## Architecture

```
flowitup-folio-prod-1 (untouched)
       │
       │   gcs:// flowitup-folio-prod-backups
       ▼
folio-restore-test (new e2-medium, ephemeral)
├── pulls latest pg_dump  →  pg_restore → data present
├── replays WAL up to ~5 min before now → data fresh
├── pulls minio-mirror   →  mc mirror back to local minio
└── runs smoke-test.sh against itself → assert correctness
```

## Related Code Files

- Create: `scripts/restore/restore-pg.sh` — pg_restore + WAL replay.
- Create: `scripts/restore/restore-minio.sh` — `mc mirror` from GCS to local.
- Create: `scripts/restore/spin-test-vm.sh` — `gcloud compute instances create folio-restore-test ...`.
- Create: `scripts/restore/run-drill.sh` — orchestrator (spin → restore → smoke → teardown).
- Update: `docs/deployment-guide.md` — runbook section for real-incident restore.

## Implementation Steps

1. Write `spin-test-vm.sh` — creates a throwaway VM (e2-medium, no static IP, no public ports) using same startup script as prod, but env points at a local Postgres + Redis + MinIO (no Cloud SQL etc., same as prod).
2. Write `restore-pg.sh`:
   - `gsutil cp gs://flowitup-folio-prod-backups/pg-dumps/<latest>.sql.zst -` → `zstd -d` → `pg_restore -d construction`.
   - Optional WAL replay: copy WAL files into pg_wal staging, set `recovery_target_time`, start Postgres in recovery mode.
3. Write `restore-minio.sh` — `mc mirror gs://flowitup-folio-prod-backups/minio-mirror/ local-minio/`.
4. Write `run-drill.sh` — chain: spin → secrets render → restore-pg → restore-minio → docker compose up → wait-healthy → smoke-test → teardown.
5. Run drill. Capture wall-clock for each step. Total target ≤ 30 min from `run-drill.sh` start.
6. If RTO > 30 min: tune (parallel restore? smaller compressed dumps? hot-replica?). Iterate.
7. Once green: schedule drill quarterly via Cloud Scheduler + Cloud Function trigger (or human calendar reminder + script).
8. Document: "what to do when prod actually dies" — mostly the same script with the live VM as target.

## Success Criteria

- [ ] `run-drill.sh` exits 0 end-to-end.
- [ ] Restored DB row counts match prod ± latest 5 min of inserts.
- [ ] Restored MinIO object count matches prod (within latest 24 h tolerance).
- [ ] Total wall-clock ≤ 30 min.
- [ ] Test VM auto-deleted after drill.
- [ ] Drill documented in `docs/deployment-guide.md` with known-good outputs.
- [ ] Calendar reminder + script ready for quarterly cadence.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| WAL replay fails on missing segment | Phase 7 alarm catches gaps before drill; archive_command exits non-zero on fail. |
| Test VM accidentally points at prod GCS for writes | `restore-*.sh` only reads from prod bucket; writes go to local volumes only; assert no `gs://flowitup-folio-prod-backups` write paths in scripts. |
| Drill takes > 30 min and balloons → operator skips it | Time-box; if first run > 30 min, fix architecture before declaring done. |
| Drill spins VM and leaks (forgotten teardown) | `trap teardown EXIT` in `run-drill.sh`; daily janitor cron deletes any `folio-restore-test*` VM > 6 h old. |
| Real incident — operator improvises and skips drill SOP | Runbook says "run `run-drill.sh --target=prod-replacement`" — same script, new flag. |
| Restored DB has different `pg_user` permissions | `pg_restore` with `--no-owner --role=construction`; tested in drill. |

## Red Team Fixes (2026-04-29)

Findings 1, 3 apply here.

### Drop WAL replay step — phase 7 no longer ships WAL

`restore-pg.sh` section "Optional WAL replay: copy WAL files into pg_wal staging, set `recovery_target_time`" is **removed**. WAL/PITR is out of scope after phase 7 fixes; restore source is the latest `pg_dump` only. RPO target is **≤ 24 h** (matches phase 7), not "≤ 5 min before now."

### Fix migration / seed commands in restore drill

Same fictional-CLI problem as phase 9. The drill's restored stack must boot with real commands:
- `docker compose run --rm -e FLASK_APP=wsgi:app api flask db upgrade` (idempotent — verifies schema is at HEAD after restore).
- Admin user comes from the restored dump itself; no re-seed needed in drill.

### Updated Success Criteria (replacements)

- [ ] Restored DB row counts match prod ± latest **24 h** of inserts (was: ± 5 min).
- [ ] No WAL replay step required; drill consumes only the latest `pg_dump`.
- [ ] Schema-at-HEAD verified post-restore via `flask db current`.

## Validation Decisions (2026-04-29 Session 1)

**Y4 — Drop quarterly drill auto-trigger.**

Original step 7: "schedule drill quarterly via Cloud Scheduler + Cloud Function trigger" + risk-row "daily janitor cron deletes any folio-restore-test* VM > 6 h old." **Removed.** The orchestration is infra-on-infra — easy to set up, easy to forget about, fails when finally needed.

**Kept:**
- ✅ `restore-pg.sh`, `restore-minio.sh`, `run-drill.sh` (manual orchestrator) — real value.
- ✅ `trap teardown EXIT` in `run-drill.sh` so a crashed run still tears down the test VM.
- ✅ Calendar reminder + 1-line runbook entry in phase 11: "every 90 days, run `run-drill.sh` and log result."

**Dropped:**
- ❌ Cloud Scheduler resource.
- ❌ Cloud Function trigger.
- ❌ `folio-restore-test*` janitor cron.

If a drill VM leaks (the trap fails for some reason), the operator notices on next billing review or the disk-usage alert. Acceptable for a manual-cadence drill.

**Effort reclaimed:** ~1.5h.
