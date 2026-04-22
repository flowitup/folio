# Phase 2 Lint-Test Job Review

**Date**: 2026-01-18
**Reviewer**: code-reviewer
**Score**: 7.5/10

## Scope

- File: `.github/workflows/ci.yml` (lines 176-227)
- Focus: lint-test job implementation

## Critical Issues (MUST FIX)

1. **No action SHA pinning** - `@v4`/`@v5` vulnerable to supply chain attacks
   - Pin to commit SHA: `actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11`

2. **Missing security comment** - Unlike version-bump job, no self-hosted runner security note

3. **Step timeouts missing** - Individual steps can hang, locking runner resources

## Warnings (SHOULD FIX)

1. **Cache key incomplete** - Add `requirements*.txt` to hash
2. **pytest-cov unused** - pyproject.toml has it, pipeline doesn't use it
3. **No explicit `continue-on-error: false`** - Relies on defaults

## Suggestions (NICE TO HAVE)

1. Parallelize ruff + black (independent checks)
2. Use setup-python built-in cache option
3. Add `--color=always` for better logs
4. Add step IDs to all steps

## Positive Observations

- Correct Python 3.11
- Proper editable install
- Good job summary
- `if: always()` on summary
- Timeout-minutes set
- Cache fallback keys

## Todo Status

| Todo | Status |
|------|--------|
| Add lint-test job definition | DONE |
| Configure Python 3.11 setup | DONE |
| Add pip caching | DONE |
| Add ruff check step | DONE |
| Add black check step | DONE |
| Add mypy step | DONE |
| Add pytest step | DONE |

**Phase 2 implementation complete. Ready for merge after critical fixes.**

## Unresolved Questions

None.
