# Phase 2: Lint & Test Job

## Context Links
- Parent: [plan.md](plan.md)
- Target: `construction-back-end/.github/workflows/ci.yml`
- Related: `construction-back-end/pyproject.toml`

## Overview
- **Date**: 2026-01-18
- **Priority**: P2
- **Implementation Status**: completed
- **Review Status**: completed (7.5/10)
- **Description**: Create lint & test job running ruff, black, mypy, pytest on all PRs and push to main

## Key Insights
- pyproject.toml has dev dependencies: pytest, pytest-cov, black, ruff, mypy
- Python version: 3.11
- ruff replaces flake8 (already configured in pyproject.toml)
- black line-length: 100, target: py311
- mypy: strict mode enabled

## Requirements

### Functional
- Run on all pull_request events
- Run on push to main
- Execute linters in order: ruff → black → mypy → pytest
- Fail fast on any linter failure

### Non-Functional
- Use self-hosted runner
- Cache pip dependencies for speed
- Clear error output for failures

## Architecture

```yaml
lint-test:
  runs-on: self-hosted
  steps:
    - checkout
    - setup python 3.11
    - cache pip
    - install deps: pip install -e ".[dev]"
    - ruff check .
    - black --check .
    - mypy .
    - pytest
```

## Related Code Files
- MODIFY: `construction-back-end/.github/workflows/ci.yml` (add job)

## Implementation Steps

1. Add `lint-test` job to ci.yml
2. Use `actions/checkout@v4`
3. Use `actions/setup-python@v5` with python-version: "3.11"
4. Add pip cache using `actions/cache@v4`
5. Install dependencies: `pip install -e ".[dev]"`
6. Add step: `ruff check .`
7. Add step: `black --check .`
8. Add step: `mypy .`
9. Add step: `pytest`
10. Optional: Add pytest coverage report

## Todo List
- [x] Add lint-test job definition
- [x] Configure Python 3.11 setup
- [x] Add pip caching
- [x] Add ruff check step
- [x] Add black check step
- [x] Add mypy step
- [x] Add pytest step

## Success Criteria
- All linters run successfully on clean code
- Pipeline fails if any linter fails
- Cache improves subsequent run times
- Works on self-hosted runner

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing deps on runner | Medium | Self-contained pip install |
| Cache miss | Low | Acceptable first-run penalty |
| mypy strict failures | Medium | Fix code or adjust config |

## Security Considerations
- No secrets required for lint/test
- Checkout only reads code, no write

## Next Steps
- Can run in parallel with Phase 1
- After both phases: test full workflow
