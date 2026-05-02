#!/usr/bin/env bash
# Phase 5 — poll a compose service until it's healthy (or 'running' with no
# healthcheck declared). Empty Health.Status is treated as ok-if-running so
# this works for the worker (compose has `healthcheck: disable: true`).
#
# Invocation:
#   /opt/folio/scripts/wait-healthy.sh <service>
# Exits 0 when healthy, 1 on timeout, 2 on bad arg.
set -euo pipefail

SVC="${1:?usage: $0 <service>}"
PROJECT="${COMPOSE_PROJECT_NAME:-folio}"
CONTAINER="${PROJECT}-${SVC}-1"
RETRIES="${RETRIES:-30}"
SLEEP_SEC="${SLEEP_SEC:-5}"

for i in $(seq 1 "$RETRIES"); do
  state=$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "missing")
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$CONTAINER" 2>/dev/null || echo "")

  if [[ "$state" == "running" ]] && [[ -z "$health" || "$health" == "healthy" ]]; then
    echo "[$SVC] ok (state=$state, health=${health:-none})"
    exit 0
  fi

  printf '[%s] not ready (try %d/%d, state=%s, health=%s)\n' \
    "$SVC" "$i" "$RETRIES" "$state" "${health:-none}"
  sleep "$SLEEP_SEC"
done

echo "[$SVC] timeout after $((RETRIES * SLEEP_SEC))s — last state=$state, health=${health:-none}" >&2
docker logs --tail 50 "$CONTAINER" >&2 2>&1 || true
exit 1
