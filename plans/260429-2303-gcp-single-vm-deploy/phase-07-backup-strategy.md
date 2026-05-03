---
phase: 7
title: "Backup Strategy"
status: pending
priority: P1
effort: "4h"
dependencies: [3]
---

# Phase 7: Backup Strategy

> **[REVISED 2026-04-29]** WAL/PITR DROPPED entirely (would have halted prod DB). RPO target downgraded honestly from "≤5 min" to **≤24 h** (last `pg_dump`). `mc mirror --remove` flag stripped. Backup uploads now run as `backup-sa` via impersonation, not `vm-runtime-sa`. HMAC keys for `mc` minted explicitly. **The `## Red Team Fixes (2026-04-29)` section at the end is authoritative**; supersedes Architecture, Implementation Steps, and the original RPO/RTO claim.

## Overview

Daily logical Postgres dumps + continuous WAL archive + nightly MinIO mirror, all to `gs://flowitup-folio-prod-backups`. Weekly disk snapshots cover the OS + everything else. Targets RPO ≤ 5 min for DB (WAL), RTO ≤ 30 min for full restore.

## Requirements

- **Functional:** Restorable snapshot of Postgres + MinIO + config exists at any point ≤ 5 min stale (DB) / ≤ 24 h (objects). All artifacts in GCS with versioning + lifecycle.
- **Non-functional:** Backup ops don't disrupt prod traffic (low-priority IO); checksums verified on each upload; cost capped (< $5/mo for backup storage).

## Architecture

```
                ┌─ pg_dump  (daily 03:00 UTC) ────────┐
Postgres 16 ────┼─ archive_command (continuous WAL) ──┼──→ GCS flowitup-folio-prod-backups
                │                                      │       /pg-dumps/YYYY-MM-DD.sql.zst
                │                                      │       /pg-wal/000000010000... (WAL files)
                │                                      │
MinIO  ─────── mc mirror (daily 03:30 UTC) ────────────┤       /minio-mirror/...
                                                       │
GCE disk ───── snapshot (weekly Sun 02:00 UTC) ────────┘  (separate snapshot system)


Lifecycle rules on bucket:
- pg-dumps/      retain 30 days, then delete
- pg-wal/        retain 7 days
- minio-mirror/  retain 30 days
- versioning ON; noncurrent versions deleted after 30 days
```

## Related Code Files

- Create: `scripts/backup/pg-dump.sh` — one-shot dump + zstd compress + gsutil cp.
- Create: `scripts/backup/pg-wal-archive.sh` — Postgres `archive_command` target.
- Create: `scripts/backup/minio-mirror.sh` — `mc alias` + `mc mirror`.
- Create: `scripts/backup/verify.sh` — periodic restore-test (downloads latest dump, restores to throwaway DB, runs checksum query).
- Create: `infra/gcp/snapshot-policy.tf` — weekly GCE snapshot schedule.
- Modify: `docker-compose.yml` — Postgres `command:` adds `archive_mode=on archive_command='...'`.

## Implementation Steps

### Postgres logical dumps
1. Add a backup container or host cron running `pg-dump.sh` at 03:00 UTC.
2. Script: `pg_dump -Fc | zstd -19 | gsutil cp - gs://flowitup-folio-prod-backups/pg-dumps/$(date -u +%F).sql.zst`.
3. Use `vm-runtime-sa` for GCS auth (already attached to VM).

### Postgres WAL archive (PITR-lite)
4. Configure Postgres in `docker-compose.yml`: `wal_level=replica`, `archive_mode=on`, `archive_command='/scripts/pg-wal-archive.sh %f %p'`.
5. `pg-wal-archive.sh` uploads each WAL segment to `gs://flowitup-folio-prod-backups/pg-wal/` with `gsutil cp`.
6. Verify by counting WAL files in GCS — should grow continuously.

### MinIO mirror
7. Cron at 03:30 UTC runs `mc mirror --overwrite --remove minio/<bucket> gs://flowitup-folio-prod-backups/minio-mirror/<bucket>/`.
8. Use a GCS HMAC key for `mc` (since `mc` speaks S3, not native GCS).

### Disk snapshots
9. Create resource policy `snapshot-weekly` in Terraform: weekly Sun 02:00 UTC, retain 4 weeks.
10. Attach policy to data disk (and boot disk).

### Verification
11. `verify.sh` runs weekly: pulls latest dump, restores to a sidecar Postgres container, runs `SELECT count(*) FROM users` (or known-row sanity check), exits non-zero on mismatch. Failure pages oncall.

### Lifecycle + cost
12. `gsutil lifecycle set lifecycle.json gs://flowitup-folio-prod-backups`. Capped retention as in architecture.
13. Monitor bucket size monthly; alert at > 50 GB.

## Success Criteria

- [ ] Day 1: dump file in `pg-dumps/` ≤ 10 MB compressed for empty DB; grows linearly.
- [ ] WAL files appearing in `pg-wal/` continuously (>= 1 every 30 min under load).
- [ ] MinIO mirror has same object count as source after first sync.
- [ ] Weekly snapshot visible in `gcloud compute snapshots list`.
- [ ] `verify.sh` succeeds in dry-run on a fresh dump.
- [ ] Bucket lifecycle correctly deletes old WAL > 7 days, dumps > 30 days.
- [ ] Total backup storage cost < $5/mo at first month end.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| `archive_command` fails silently → WAL gap | `pg-wal-archive.sh` exits non-zero on failure; Postgres halts new commits — alert fires fast. |
| Dump succeeds but corrupt | Weekly `verify.sh` restores it; run before production cutover. |
| Bucket retention too aggressive → can't restore old state | Conservative defaults (30 d dumps); user changes after restore drill (phase 10). |
| Backup IO swamps prod DB | `pg_dump` from a read replica? Out of scope here (Option B territory). Mitigate with `nice -n 19` and 03:00 UTC timing. |
| GCS HMAC key for MinIO leaks | Stored in Secret Manager (phase 6); rotate quarterly. |
| Snapshot policy detached after disk recreate | Terraform attaches as part of disk resource; CI plan-check catches drift. |
| Backup bucket deletion (fat-finger) | Bucket has `retention-policy` lock + Object Versioning; user without `storage.admin` can't bypass. |

## Red Team Fixes (2026-04-29)

Findings 3, 5, 9, 13 apply here. Major rewrites to backup architecture.

### DROP WAL archive — RPO target revised to ≤24 h (honest)

Original plan claimed RPO ≤ 5 min via continuous `archive_command`. **Removed.** Reasons:
1. `postgres:16-alpine` has no `gsutil`, no `gcloud`, no `zstd` — `archive_command='/scripts/pg-wal-archive.sh'` would fail at first WAL switch and **halt all DB writes** (Postgres semantics).
2. Building a custom Postgres image (`FROM postgres:16` + apt google-cloud-cli + COPY script) is extra surface and image bloat for an early-stage solo deploy.
3. Brainstorm originally listed RPO 24 h (dump) + 5 min (PITR) as separate options; phase 7 had collapsed them. Reverted.

**Action:** Remove `archive_mode=on archive_command='...'` from `docker-compose.yml`. Remove `pg-wal-archive.sh` from "Related Code Files." Remove `pg-wal/` GCS prefix from architecture diagram. Update RPO target throughout to **≤ 24 h** (last successful `pg_dump`). WAL/PITR is a deferred enhancement — revisit when first DB scare or paying-customer-count justifies the work (matches brainstorm decision-log).

### `mc mirror` — drop `--remove`, add divergence guard

Original: `mc mirror --overwrite --remove minio/<bucket> gs://...`. The `--remove` flag means "delete in destination what's missing in source" — a single bad MinIO state (corrupted volume, accidental wipe) propagates to the GCS mirror within 24 h, destroying recovery.

**Replacement:**
```bash
# scripts/backup/minio-mirror.sh
mc mirror --overwrite minio/construction-attachments \
  gs://flowitup-folio-prod-backups/minio-mirror/construction-attachments/

# Sanity gate: refuse if source object count drops > 5% vs last run
SRC_COUNT=$(mc ls --recursive minio/construction-attachments | wc -l)
LAST_COUNT=$(cat /var/lib/folio/last-mc-count 2>/dev/null || echo 0)
if [ "$LAST_COUNT" -gt 0 ] && [ "$SRC_COUNT" -lt $((LAST_COUNT * 95 / 100)) ]; then
  echo "ABORT: source dropped >5% ($LAST_COUNT → $SRC_COUNT), refusing to mirror" >&2
  exit 1
fi
echo "$SRC_COUNT" > /var/lib/folio/last-mc-count
```

Pair with a monthly archival snapshot to a second bucket `flowitup-folio-prod-backups-archive` (write-once, 365-day retention lock). The archive bucket is the disaster-recovery source of truth; the daily mirror is for routine restore convenience.

### Backups run as `backup-sa`, NOT `vm-runtime-sa`

Original step 3: "Use `vm-runtime-sa` for GCS auth (already attached to VM)." **Wrong** — that gives the runtime SA write to backups, so a Flask compromise = backup wipe.

**Replacement:** All backup scripts impersonate `backup-sa`:
```bash
gcloud auth print-access-token --impersonate-service-account=backup-sa@flowitup-folio-prod.iam.gserviceaccount.com
# OR set in script:
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=backup-sa@flowitup-folio-prod.iam.gserviceaccount.com
gsutil cp dump.sql.zst gs://flowitup-folio-prod-backups/...
```

`vm-runtime-sa` needs `roles/iam.serviceAccountTokenCreator` on `backup-sa` to impersonate. `backup-sa` has only `roles/storage.objectCreator` on the bucket — no delete, no overwrite-by-different-version. `vm-runtime-sa` has NO direct write to the backup bucket.

### `mc` HMAC keys explicit (Finding 13)

`mc` speaks S3, not GCS native. Mint HMAC for `backup-sa` (phase 1 fix), store in Secret Manager (`folio-gcs-hmac-access-key`, `folio-gcs-hmac-secret-key`), `mc alias set gcs https://storage.googleapis.com $ACCESS $SECRET --api S3v4`. Document the carve-out in `infra/gcp/README.md` — this is the ONLY non-`deploy-sa` SA key in the system.

### Updated success criteria (replacements)

- [ ] **RPO target = 24 h** (changed from 5 min). Documented in phase 11 runbook.
- [ ] No `archive_command` / `archive_mode` in `docker-compose.yml`.
- [ ] `mc mirror` script aborts on >5% source-count drop; last-count file maintained.
- [ ] `gsutil ls -p flowitup-folio-prod gs://flowitup-folio-prod-backups` from `vm-runtime-sa` returns 403 on write attempt; only `backup-sa` (impersonated) can write.
- [ ] Bucket retention policy 7 d (working) + archive bucket retention 365 d (locked).
- [ ] HMAC keys live in SM only — never in repo, never in GitHub Secrets.

### Removed risk row — no longer applicable

| ~~`archive_command` fails silently → WAL gap~~ | ~~`pg-wal-archive.sh` exits non-zero on failure; Postgres halts new commits — alert fires fast.~~ | **DROPPED — WAL no longer in scope.** |
