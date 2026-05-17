# Folio

Umbrella repo for Folio. Two submodules + parent docs + infra + deploy
workflows.

```
folio-back-end/   → Flask 3 + hexagonal + SQLAlchemy + RQ        (flowitup/folio-back-end)
folio-front-end/  → Next.js 16 + next-intl + Tailwind + shadcn   (flowitup/folio-front-end)
docs/             → architecture, code standards, deployment guide
infra/            → GCP bootstrap, Cloudflare, CI templates
scripts/          → deploy-runner, smoke, backups
```

Live: https://folio.flowitup.com

---

## Local development

The base `docker-compose.yml` requires every secret-bearing variable
(`${VAR:?required}`) so an accidental `docker compose up` on the VM cannot
boot prod with development defaults. For local dev, layer the dev overlay
which fills in safe-for-dev values:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

Production on the VM uses the prod overlay (values come from
`/opt/folio/.env`, rendered from Secret Manager):

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## Deploys

Both backend and frontend deploy automatically when a new version tag is
created in their submodule. No manual SSH needed.

### Trigger

```
folio-back-end (or folio-front-end) merge to master
  → CI version-bump → tag v1.2.3 → release job
  → repository_dispatch to flowitup/folio
  → parent .github/workflows/deploy-{backend,frontend}.yml
  → build+push image to AR → IAP SSH → deploy-runner.sh → smoke
  → commit submodule pointer bump on parent master
```

The submodule pointer in parent `master` always reflects the SHA running
in prod. `git submodule status` from a fresh clone shows the live SHAs.

### Manual deploy (workflow_dispatch)

Use when a release didn't auto-dispatch (e.g. PAT expired, dispatch step
failed) or you need to redeploy a specific SHA.

```bash
gh workflow run deploy-backend.yml  -R flowitup/folio \
  -f version=1.2.3 -f sha=<7-40-hex-sha>

gh workflow run deploy-frontend.yml -R flowitup/folio \
  -f version=1.2.3 -f sha=<7-40-hex-sha>
```

### Status

- Live: https://folio.flowitup.com — `/health` (BE), `/` (FE).
- Workflow runs: https://github.com/flowitup/folio/actions
- Last deployed SHAs: `git submodule status` on parent master.

### Rollback

Forward-only is preferred — push a fix and let CI auto-deploy. Hard
rollback to a prior image:

```bash
gcloud compute ssh flowitup-folio-prod-1 \
  --tunnel-through-iap --zone=europe-west1-b \
  -- '/opt/folio/scripts/rollback.sh api'         # auto-detects previous SHA
  # or  '/opt/folio/scripts/rollback.sh api <sha>'  # explicit
```

After hard rollback the parent submodule pointer is stale. Bump it back
manually:

```bash
cd ~/workspaces/folio/folio-back-end && git fetch && git checkout <rollback-sha>
cd .. && git add folio-back-end \
  && git commit -m "chore(deploy): rollback folio-back-end → <sha> [skip ci]" \
  && git push origin master
```

Full incident playbook: `docs/deployment-guide.md` §4.

### Required secrets

Parent repo `flowitup/folio` (one-time setup —
`plans/260503-0913-parent-auto-deploy-on-version-bump/phase-06-secrets-setup-runbook.md`):

- `GCP_WIF_PROVIDER` — Workload Identity Federation provider resource path,
  e.g. `projects/<num>/locations/global/workloadIdentityPools/github-actions/providers/github`.
- `GCP_SA_EMAIL` — service account the WIF binding impersonates,
  `deploy-sa@flowitup-folio-prod.iam.gserviceaccount.com`. Org policy
  `iam.disableServiceAccountKeyCreation` blocks JSON keys, so we use OIDC
  via WIF — no `GCP_SA_KEY` needed, no key rotation.
- `CF_API_TOKEN` — Cloudflare token, zone-scoped, `Cache Purge:Edit` only.
- `CF_ZONE_ID` — `flowitup.com` zone ID.
- `SUBMODULE_TOKEN` — fine-grained PAT, scoped to `flowitup/folio-back-end`
  + `flowitup/folio-front-end` with `Contents:read` + `Metadata:read`.
  REQUIRED — both submodules are private and `GITHUB_TOKEN` on parent
  cannot read other private repos in the org.

Each submodule (`folio-back-end`, `folio-front-end`):

- `PARENT_DISPATCH_TOKEN` — fine-grained PAT scoped to `flowitup/folio`
  with `Contents: Read and write` + `Metadata: Read-only` (the
  `repository_dispatch` API requires `Contents: write` for fine-grained
  PATs). Used to send `repository_dispatch` after release.

### Concurrency + safety

- `concurrency.group=deploy-prod-backend` / `deploy-prod-frontend` —
  two close pushes serialize, never race.
- Smoke step fails the workflow loud if `/health` or `/` doesn't 200.
- Submodule pointer push uses `git pull --rebase` to avoid race with
  human pushes.
- `[skip ci]` in commit message prevents recursive triggers (defensive;
  parent has no CI on master today).

---

## Docs

- `docs/deployment-guide.md` — operational truth (deploy, rollback,
  incidents, recovery).
- `docs/system-architecture.md` — topology + data flow.
- `docs/code-standards.md` — conventions across BE + FE.
- `docs/code-standards-backend.md` / `docs/code-standards-frontend.md`.
- `docs/project-overview-pdr.md` — what + why.
