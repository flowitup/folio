---
phase: 5
title: "CI/CD Pipeline"
status: pending
priority: P1
effort: "4h"
dependencies: [3, 6]
---

# Phase 5: CI/CD Pipeline

> **[REVISED 2026-04-29]** SSH transport changed (raw `ssh` → `gcloud compute ssh --tunnel-through-iap`); migrations now run BEFORE traffic swap; CF cache purge added on frontend deploys; `wait-healthy.sh` updated for worker (no healthcheck); `flask seed admin` replaced with `python scripts/seed.py --with-admin`. **YAGNI Y5:** worker locked to shared API image; `deploy-worker.yml` deleted from scope. **The `## Red Team Fixes` and `## Validation Decisions` sections at the end are authoritative**; supersede Architecture, Implementation Steps, and the deploy-worker workflow file.

## Overview

GitHub Actions workflows that build Docker images for `folio-back-end` and `folio-front-end`, push to Artifact Registry, then SSH into the VM to `docker compose pull && up -d`. Triggered on push to `main` of each submodule and on monorepo updates. Includes rollback path.

## Requirements

- **Functional:** Push to `main` → image built → image pushed → VM pulls → service restarted → healthcheck passes within 5 min. Rollback restores previous tag in <2 min.
- **Non-functional:** No production secrets in CI; least-privilege SA; per-service deploys (don't restart unrelated containers); concurrency lock prevents overlapping deploys.

## Architecture

```
GitHub repo (push to main)
        │
        ▼
  GitHub Actions runner (ubuntu-latest)
   ├─ checkout
   ├─ google-github-actions/auth (uses GCP_SA_KEY from secrets)
   ├─ docker/build-push-action
   │   └─ tags: ${SHA}, latest
   ├─ push to AR: europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/<svc>:${SHA}
   └─ ssh -i $SSH_KEY deploy@<vm-ip-or-tunnel> \
        "cd /opt/folio && \
         docker compose pull <svc> && \
         docker compose up -d --no-deps <svc> && \
         scripts/wait-healthy.sh <svc>"
```

GitHub Secrets:
- `GCP_SA_KEY` — `deploy-sa` JSON key.
- `DEPLOY_SSH_KEY` — private SSH key for `deploy@flowitup-folio-prod-1`.
- `DEPLOY_HOST` — VM hostname/IP or `cloudflared` access alias.

## Related Code Files

- Create: `.github/workflows/deploy-api.yml` (in `folio-back-end` submodule).
- Create: `.github/workflows/deploy-frontend.yml` (in `folio-front-end` submodule).
- Create: `.github/workflows/deploy-worker.yml` (or share with API workflow).
- Create: `scripts/deploy/wait-healthy.sh` — polls `docker inspect <svc>` until healthy or timeout.
- Create: `scripts/deploy/rollback.sh` — `docker compose pull <svc>:${PREV_SHA} && up -d`.
- Modify: `docker-compose.yml` — image refs use `${IMAGE_TAG:-latest}` so deploy can pin SHA.

## Implementation Steps

1. Create `deploy-sa` JSON key, store in GitHub Secrets as `GCP_SA_KEY`. Roles: `roles/artifactregistry.writer` only.
2. Generate SSH keypair for `deploy` user. Public key into VM `~/.ssh/authorized_keys`. Private into GitHub Secrets `DEPLOY_SSH_KEY`.
3. Write `deploy-api.yml` workflow:
   - `on: push: branches: [main]`, `paths: ['Dockerfile', 'src/**', 'requirements.txt']`.
   - `concurrency: group: deploy-api, cancel-in-progress: false`.
   - Auth → build → push → ssh deploy → healthcheck → mark success.
   - On failure: post to Discord/email, optionally auto-rollback.
4. Mirror for `deploy-frontend.yml` with frontend paths.
5. Worker either reuses API image (same Dockerfile, different command) or has its own workflow. Default: same image, `docker compose up -d worker` after API succeeds.
6. `wait-healthy.sh`: 30 retries × 5 s polling `docker inspect --format '{{.State.Health.Status}}'`. Fail loud.
7. `rollback.sh`: takes optional `<svc>` and `<sha>`; defaults to previous tag from AR (`gcloud artifacts docker tags list`).
8. Add a manual `workflow_dispatch` rollback workflow for one-click revert.
9. Document in `docs/deployment-guide.md`: how to deploy, how to roll back, how to read logs.

## Success Criteria

- [ ] Push to `folio-back-end` main → API redeploys with no other service touched.
- [ ] Push to `folio-front-end` main → frontend redeploys; API container untouched.
- [ ] Build + deploy + healthy < 5 min for either submodule.
- [ ] Manual rollback workflow restores previous SHA in < 2 min.
- [ ] Concurrent pushes serialized (no two deploys racing).
- [ ] No production secret values appear anywhere in workflow logs.
- [ ] Failed deploy → Discord/email alert fires.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| SSH key in CI compromised → full VM access | Restrict deploy user (no sudo, docker group only); rotate key quarterly; use `command="..."` in `authorized_keys` to scope. |
| Deploy mid-DB-migration → broken state | Run migrations as a separate step before `up -d` of api; only then swap traffic. |
| Force-pushed `main` reverts to bad image tagged `latest` | Workflow tags by SHA, not just `latest`; rollback uses SHA, not `latest`. |
| Concurrency kills in-flight migration | `cancel-in-progress: false` keeps in-flight deploys; warn in runbook. |
| SA key leak via runner cache | `actions/checkout` with `persist-credentials: false`; SA key only in env, not artifacts. |
| Deploy works but healthcheck flakes | `wait-healthy.sh` 2.5-min budget; if exhausted, alert + auto-rollback. |

## Red Team Fixes (2026-04-29)

Findings 1, 2, 6, 7, 12, 14 apply here. Override architecture and steps as follows.

### SSH transport — gcloud IAP tunnel, NOT raw ssh

Plan originally used `ssh -i $SSH_KEY deploy@<vm-ip>` from `ubuntu-latest`. **Blocked by firewall** (phase 2 allows port 22 from IAP CIDR only). Replace with:

```yaml
- uses: google-github-actions/auth@v2
  with:
    credentials_json: ${{ secrets.GCP_SA_KEY }}     # deploy-sa
- uses: google-github-actions/setup-gcloud@v2
- name: Deploy via IAP tunnel
  run: |
    gcloud compute ssh deploy@flowitup-folio-prod-1 \
      --tunnel-through-iap \
      --zone=europe-west1-b \
      --command="/opt/folio/scripts/deploy-runner.sh ${{ github.sha }} api"
```

`deploy-sa` needs `roles/iap.tunnelResourceAccessor` (added in phase 1 fixes). `DEPLOY_SSH_KEY` GitHub secret is **deleted** — IAP authenticates via the SA, not an SSH key. The forced-command (`deploy-runner.sh`) on the VM scopes what the runner can do (no general shell).

### Per-deploy migrations — explicit step

The `up -d --no-deps api` flow originally **skipped migrations entirely**. Add:

```bash
# /opt/folio/scripts/deploy-runner.sh
set -euo pipefail
SHA=$1
SVC=$2

cd /opt/folio
export IMAGE_TAG=$SHA

# 1. Pull new image
docker compose pull "$SVC"

# 2. Run migrations BEFORE swapping traffic (only when api or worker deploys)
if [ "$SVC" = "api" ] || [ "$SVC" = "worker" ]; then
  docker compose run --rm \
    -e FLASK_APP=wsgi:app \
    api flask db upgrade
fi

# 3. Swap container
docker compose up -d --no-deps "$SVC"

# 4. Wait for health
/opt/folio/scripts/wait-healthy.sh "$SVC"
```

The `-e FLASK_APP=wsgi:app` is required because the API image's `CMD` is `gunicorn 'app:create_app()'`, not the Flask CLI; without `FLASK_APP`, `flask db upgrade` exits with "Could not locate a Flask application." (See Finding 1.)

### `wait-healthy.sh` — handle worker (no healthcheck)

Worker has `healthcheck: disable: true` (compose). `docker inspect --format '{{.State.Health.Status}}'` returns empty for it. The script must:

```bash
# /opt/folio/scripts/wait-healthy.sh
SVC=$1
for i in $(seq 1 30); do
  STATE=$(docker inspect --format '{{.State.Status}}' "folio-${SVC}-1")
  HEALTH=$(docker inspect --format '{{.State.Health.Status}}' "folio-${SVC}-1" 2>/dev/null || echo "")
  if [ "$STATE" = "running" ] && { [ -z "$HEALTH" ] || [ "$HEALTH" = "healthy" ]; }; then
    echo "ok"; exit 0
  fi
  sleep 5
done
echo "timeout"; exit 1
```

Empty `Health.Status` (= no healthcheck declared) is treated as "fine if running."

### Cloudflare cache purge on frontend deploy — net new step

`/_next/static/*` has 1-month edge TTL. Without a purge step, deploys can leave users on a stale build-id (404 for new chunks, white screen). Add to `deploy-frontend.yml` after `up -d frontend` succeeds:

```yaml
- name: Purge Cloudflare cache
  run: |
    curl -fSs -X POST \
      -H "Authorization: Bearer ${{ secrets.CF_API_TOKEN }}" \
      -H "Content-Type: application/json" \
      -d '{"hosts":["${{ secrets.PROD_DOMAIN }}"]}' \
      "https://api.cloudflare.com/client/v4/zones/${{ secrets.CF_ZONE_ID }}/purge_cache"
```

CF API token (zone-scoped, `Cache Purge:Edit` permission only) added to GitHub Secrets.

### Reuse existing `scripts/smoke-test.sh` — DON'T create a new file

A 569-line `scripts/smoke-test.sh` already supports `--host`, admin seeding, login probe. Phase 5/9 EXTEND it; do not create `scripts/test/smoke-test.sh`. (See Finding 14.)

### Updated Success Criteria (replacements)

- [ ] Push to `folio-back-end` main → API redeploys, **migrations run before traffic swap**.
- [ ] CI uses `gcloud compute ssh --tunnel-through-iap`; raw `ssh` is removed from workflows.
- [ ] `wait-healthy.sh` returns ok for worker (`State.Status==running`, no healthcheck).
- [ ] Frontend deploy ends with successful CF cache purge (CI log shows 200 from CF API).
- [ ] No `DEPLOY_SSH_KEY` GitHub Secret; deploy auth = `GCP_SA_KEY` only.

## Validation Decisions (2026-04-29 Session 1)

**Y5 — Worker decision locked: shared API image, no separate workflow.**

Original step 5: "Worker either reuses API image (same Dockerfile, different command) or has its own workflow. Default: same image." **Locked to: shared image.** Worker uses the same Dockerfile via `command: python -m stack.queue.rq_worker` (already in `docker-compose.yml`). No separate `deploy-worker.yml` workflow.

**Action:**
- Delete: `.github/workflows/deploy-worker.yml` from "Related Code Files."
- `deploy-api.yml` covers both: after `up -d --no-deps api` succeeds, immediately run `up -d --no-deps worker` so both restart with the new image.
- Migration step in `deploy-runner.sh` runs once (api covers both app + worker since same image).

**Effort reclaimed:** ~1h (one fewer workflow file + simpler concurrency reasoning).
