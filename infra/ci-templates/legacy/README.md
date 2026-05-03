# Legacy CI templates

These two YAML files were the original Phase-5 plan: copy them into each
submodule's `.github/workflows/` to deploy on push-to-main with paths-filter.

**Status: superseded.** The parent repo `flowitup/folio` now owns deploy via:

- `.github/workflows/deploy-backend.yml`  ← listens for `repository_dispatch:deploy-api`
- `.github/workflows/deploy-frontend.yml` ← listens for `repository_dispatch:deploy-frontend`

Each submodule's `release` job dispatches the event after creating a tag. See
parent `README.md` → "Deploys" and `docs/deployment-guide.md` §3.1.

**Do not copy these files into a submodule.** Doing so would double-deploy
and race the parent workflow. They are kept here only as design-time reference
for the build+push+IAP-SSH shape (which the parent reuses).

If you need to revive submodule-side deploys (e.g. the parent dies):

1. Copy the relevant YAML into the submodule's `.github/workflows/`.
2. Disable / delete the corresponding parent workflow.
3. Add `GCP_SA_KEY`, `CF_API_TOKEN`, `CF_ZONE_ID` to the submodule secrets.
