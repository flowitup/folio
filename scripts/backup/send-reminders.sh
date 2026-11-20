#!/usr/bin/env bash
# Scheduled reminder pushes (owner decision QĐ-9): "no attendance logged today" for
# managers (19:30 Paris, working days), overdue factures for company admins (Monday
# morning) and the month summary (the 1st). Runs ON THE VM via cron every 15 minutes
# (see install-backup-cron.sh), inside the running api container so it uses the same
# image, env and push settings (PUSH_PROVIDER, EXPO_ACCESS_TOKEN) as the API.
#
# The python script decides what is due from the Europe/Paris wall clock, so the UTC
# host cron and daylight saving need nothing here, and it records every send, so a
# re-run (or a run that overlaps the previous one) never pushes twice.
#
# Failure modes:
#   - api container not running          → exit 2, log
#   - the reminder script exits non-zero → exit 3, log
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/folio}"
ENV_FILE="${ENV_FILE:-/opt/folio/.env}"

log() { /usr/bin/logger -t send-reminders -s "$*" 2>&1; }

cd "$COMPOSE_DIR"
COMPOSE=(/usr/bin/docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file "$ENV_FILE")

if [[ -z "$("${COMPOSE[@]}" ps -q api 2>/dev/null)" ]]; then
  log "ERROR: api container not running"
  exit 2
fi

# PYTHONPATH=/app: `python scripts/x.py` puts /app/scripts first on sys.path, so the
# repo-root modules the script imports (wiring, config) would not be found.
if ! "${COMPOSE[@]}" exec -T -e PYTHONPATH=/app api python scripts/send_scheduled_reminders.py; then
  log "ERROR: reminder run failed"
  exit 3
fi
