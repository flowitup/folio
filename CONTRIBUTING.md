# Contributing to Folio

Folio is a monorepo with two git submodules (`folio-back-end`, `folio-front-end`).
Code changes go into the submodules — the parent repo holds deploy workflows,
compose files, and submodule SHA pointers.

## Working in submodules

- `cd folio-back-end && git checkout -b my-branch` — you're now in a separate repo.
- Push to the submodule's origin, open a PR there.
- A merge to `master` in a submodule triggers auto-deploy via CI.

## Schema changes that span BE + FE

### Enum-value renames

Renaming a Postgres `ENUM` value that both backend and frontend reference
requires a **three-phase deploy** to avoid downtime. A naive rename creates
a 5–10 minute window where the FE sends the old value and the BE rejects it
with 422.

See the **Enum-value rename runbook** in `docs/deployment-guide.md §7.1` for
the full three-phase pattern, worked example, checklist, and rollback notes.

The short version:

1. **BE release 1** — add the new enum value, accept BOTH old + new in the API,
   map old→new on read.
2. **FE release** — switch to the new value.
3. **BE release 2** — drop the old value from the Pydantic schema, remove the mapping.

Do **not** rename an enum value in a single BE+FE deploy pair.

## Commit conventions

- `feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `security:` prefixes.
- Parent-repo commits should only touch: docs, compose files, deploy workflows,
  infra, scripts, or a submodule pointer bump.
- Never commit Python or TypeScript source into the parent.
