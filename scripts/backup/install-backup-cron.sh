#!/usr/bin/env bash
# Install the nightly backup jobs the way the prod host (Hetzner folio-prod-1)
# runs them: pg-dump.sh and minio-mirror.sh in /usr/local/bin, scheduled by
# /etc/cron.d/folio-backups. Run as root on the host, from a copy of this
# directory (scripts/backup/).
#
# Cron schedule (UTC — the host clock is UTC):
#   03:00 daily  →  pg-dump.sh
#   03:30 daily  →  minio-mirror.sh
#
# verify-latest-dump.sh (weekly restore test) is deliberately NOT installed:
# it needs gsutil and the GCP VM's own service account, and the host has
# neither — see scripts/README.md.
#
# No log files or logrotate: both scripts log through `logger`, so their status
# lines land in journald (`journalctl -t pg-dump -t minio-mirror`).
set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR=/usr/local/bin
CRON_FILE=/etc/cron.d/folio-backups

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root" >&2; exit 1; }

# 1. Scripts — check both before installing either.
for s in pg-dump.sh minio-mirror.sh; do
  [[ -f "${SRC_DIR}/${s}" ]] || { echo "ERROR: ${SRC_DIR}/${s} missing" >&2; exit 2; }
done
for s in pg-dump.sh minio-mirror.sh; do
  install -o root -g root -m 755 "${SRC_DIR}/${s}" "${BIN_DIR}/${s}"
done

# 2. Cron file — same content as the host's (checked 2026-09-26).
cat > "$CRON_FILE" <<'EOF'
# Folio backups (UTC) - pg dump 03:00, minio mirror 03:30
0 3 * * * root /usr/local/bin/pg-dump.sh
30 3 * * * root /usr/local/bin/minio-mirror.sh
EOF
chmod 644 "$CRON_FILE"
chown root:root "$CRON_FILE"

echo "installed: ${BIN_DIR}/pg-dump.sh ${BIN_DIR}/minio-mirror.sh ${CRON_FILE}"
# No same-day smoke test: once today's dump exists, a re-run can't replace it
# and pg-dump.sh fails by design (see scripts/README.md).
echo "after the next run (03:00 / 03:30 UTC): journalctl -t pg-dump -t minio-mirror --since today"
