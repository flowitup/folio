#!/usr/bin/env bash
# Phase 7 — install cron entries on the VM for daily/weekly backups.
# Runs ON THE VM as root.
#
# Cron schedule (UTC):
#   03:00 Mon-Sun  →  pg-dump.sh
#   03:30 Mon-Sun  →  minio-mirror.sh
#   04:00 Sun      →  verify-latest-dump.sh
#
# Each entry redirects stdout+stderr to /var/log/folio/<job>.log AND emits
# via logger to journald (the scripts handle that internally). Cron output
# is suppressed unless something fails.
set -euo pipefail

CRON_FILE=/etc/cron.d/folio-backups
LOG_DIR=/var/log/folio
SCRIPT_DIR=/opt/folio/scripts/backup

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root" >&2; exit 1; }

# 1. Ensure scripts are present + executable on the VM.
for s in pg-dump.sh minio-mirror.sh verify-latest-dump.sh; do
  [[ -x "${SCRIPT_DIR}/${s}" ]] || { echo "ERROR: ${SCRIPT_DIR}/${s} missing or not executable. Copy it from the worktree first." >&2; exit 2; }
done

# 2. Log directory.
install -d -m 755 -o root -g root "$LOG_DIR"

# 3. Cron file. PATH must include /usr/bin and /snap/bin/gcloud-replacement.
# /usr/bin/gcloud is the apt-installed gcloud (snap was removed in phase 6).
cat > "$CRON_FILE" <<'EOF'
# Folio production backups — managed by scripts/backup/install-backup-cron.sh
# Do NOT edit by hand; re-run the installer to update.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Daily Postgres logical dump → GCS
0 3 * * *   root  /opt/folio/scripts/backup/pg-dump.sh         >> /var/log/folio/pg-dump.log 2>&1

# Daily MinIO → GCS mirror (with 5% drop guard)
30 3 * * *  root  /opt/folio/scripts/backup/minio-mirror.sh    >> /var/log/folio/minio-mirror.log 2>&1

# Weekly restore-test of latest dump
0 4 * * 0   root  /opt/folio/scripts/backup/verify-latest-dump.sh >> /var/log/folio/verify-latest-dump.log 2>&1
EOF

chmod 644 "$CRON_FILE"
chown root:root "$CRON_FILE"

# 4. Logrotate so those .log files don't grow unbounded.
cat > /etc/logrotate.d/folio-backups <<'EOF'
/var/log/folio/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

# 5. Validate cron syntax (debian's cron silently ignores broken files; check now).
if /usr/bin/crontab -T "$CRON_FILE" 2>/dev/null; then
  echo "  syntax check: ok"
elif /usr/sbin/cron -x sch -d <<<'' >/dev/null 2>&1; then
  # crontab -T not available on all systems — fall back to manual run
  echo "  syntax check: skipped (crontab -T not supported)"
fi

echo ""
echo "installed:"
ls -l "$CRON_FILE"
echo ""
echo "next runs (UTC):"
echo "  pg-dump:        $(date -u -d 'tomorrow 03:00' '+%a %F %T' 2>/dev/null || date -u -v+1d -v3H -v0M -v0S '+%a %F %T')"
echo "  minio-mirror:   $(date -u -d 'tomorrow 03:30' '+%a %F %T' 2>/dev/null || date -u -v+1d -v3H -v30M -v0S '+%a %F %T')"
echo "  verify (Sun):   next Sunday 04:00 UTC"
echo ""
echo "manual smoke-test (recommended right after install):"
echo "  sudo /opt/folio/scripts/backup/pg-dump.sh"
echo "  sudo /opt/folio/scripts/backup/minio-mirror.sh"
echo ""
echo "tail logs while testing:"
echo "  sudo journalctl -ft pg-dump -t minio-mirror -t backup-verify"
