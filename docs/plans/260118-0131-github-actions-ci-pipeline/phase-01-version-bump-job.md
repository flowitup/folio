# Phase 1: Version Bump Job

## Context Links
- Parent: [plan.md](plan.md)
- Target: `construction-back-end/.github/workflows/ci.yml`
- Related: `construction-back-end/pyproject.toml`

## Overview
- **Date**: 2026-01-18
- **Priority**: P2
- **Implementation Status**: completed
- **Review Status**: completed
- **Description**: Create version bump job that runs on PR merge to main, computes new version from PR labels, updates pyproject.toml

## Key Insights
- Version in pyproject.toml at line 3: `version = "0.1.0"`
- Need to extract PR labels from merged commit
- Use `[skip ci]` in commit message to prevent infinite loop
- GitHub context provides PR info via `github.event.pull_request`

## Requirements

### Functional
- Detect PR labels: `version:major`, `version:minor`, `version:patch`
- Compute new semver based on label
- Update `pyproject.toml` version field
- Commit and push change

### Non-Functional
- Only run on push to main (merged PR)
- Skip if no version label present
- Commit message must include `[skip ci]`

## Architecture

```yaml
version-bump:
  runs-on: self-hosted
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  steps:
    - checkout with token (for push access)
    - get PR labels from merge commit
    - compute new version
    - update pyproject.toml with sed/python
    - git commit & push with [skip ci]
```

## Related Code Files
- CREATE: `construction-back-end/.github/workflows/ci.yml`
- MODIFY: none (pyproject.toml modified by workflow at runtime)

## Implementation Steps

1. Create `.github/workflows/` directory if not exists
2. Create `ci.yml` with version-bump job
3. Use `actions/checkout@v4` with `token: ${{ secrets.GITHUB_TOKEN }}`
4. Get merged PR number from commit message or API
5. Fetch PR labels using GitHub CLI or API
6. Parse current version from pyproject.toml
7. Compute new version based on label type
8. Use sed or python to update version in pyproject.toml
9. Configure git user for commit
10. Commit with message: `chore: bump version to X.Y.Z [skip ci]`
11. Push to main

## Todo List
- [ ] Create workflow file structure
- [ ] Implement label detection logic
- [ ] Implement version computation
- [ ] Implement pyproject.toml update
- [ ] Add commit and push steps
- [ ] Test with dry-run

## Success Criteria
- Version bumps correctly for each label type
- No CI triggered on version commit
- Works on self-hosted runner
- Fails gracefully if no version label

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| Infinite CI loop | High | Use [skip ci] in commit |
| Push permission denied | High | Use GITHUB_TOKEN with write |
| Wrong version computed | Medium | Add validation step |

## Security Considerations
- Use `GITHUB_TOKEN` (built-in), no custom PAT needed for same-repo push
- Limit permissions in workflow to `contents: write`

## Next Steps
- Depends on: none
- Blocks: Phase 2 (can run in parallel)
