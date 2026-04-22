---
title: "GitHub Actions CI Pipeline for Backend"
description: "CI pipeline with version bumping, linting (ruff, black, mypy), and pytest on self-hosted runner"
status: completed
priority: P2
effort: 2h
branch: main
tags: [ci-cd, github-actions, python, linting, testing]
created: 2026-01-18
---

# GitHub Actions CI Pipeline

## Overview

Create CI pipeline for `construction-back-end/` Python project with:
- Self-hosted runner (`runs-on: self-hosted`)
- Automatic version bumping based on PR labels
- Python linting and testing

## Phases

| Phase | Description | Status | Effort |
|-------|-------------|--------|--------|
| [Phase 1](phase-01-version-bump-job.md) | Version bump job on PR merge | completed | 1h |
| [Phase 2](phase-02-lint-test-job.md) | Lint & test job | completed | 1h |

## Architecture

```
.github/workflows/ci.yml
├── on: pull_request (all) + push (main)
├── job: version-bump
│   ├── runs-on: self-hosted
│   ├── if: github.event_name == 'push' && contains labels
│   ├── compute version from PR labels
│   ├── update pyproject.toml
│   └── commit with [skip ci]
└── job: lint-test
    ├── runs-on: self-hosted
    ├── setup python 3.11
    ├── install deps [dev]
    ├── ruff check
    ├── black --check
    ├── mypy
    └── pytest
```

## Version Labels

| Label | Action | Example |
|-------|--------|---------|
| `version:major` | X.0.0 | 0.1.0 → 1.0.0 |
| `version:minor` | 0.X.0 | 0.1.0 → 0.2.0 |
| `version:patch` | 0.0.X | 0.1.0 → 0.1.1 |

## Files to Create

- `construction-back-end/.github/workflows/ci.yml`

## Dependencies

- Self-hosted GitHub Actions runner configured
- Python 3.11 installed on runner
- Git configured for commits on runner

## Success Criteria

- [ ] Pipeline triggers on all PRs
- [ ] Pipeline triggers on push to main
- [ ] Version bumps correctly based on labels
- [ ] Version commit includes [skip ci]
- [ ] All linters run in order: ruff → black → mypy → pytest
