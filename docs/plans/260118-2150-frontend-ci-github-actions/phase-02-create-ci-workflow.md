# Phase 02: Create CI Workflow

## Context Links
- [Parent Plan](plan.md)
- [Phase 01: Setup Test Framework](phase-01-setup-test-framework.md)
- [Phase 03: Write Unit Tests](phase-03-write-unit-tests.md)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Backend CI Reference](../../../construction-back-end/.github/workflows/ci.yml)

## Overview

| Field | Value |
|-------|-------|
| Priority | P2 |
| Status | done |
| Review Status | approved |
| Effort | 1.5h |

Create GitHub Actions CI workflow with version-bump, lint, type check, tests, build, and release stages.

## Key Insights

- Use `actions/setup-node@v4` with caching
- Parallel jobs for lint + type check (independent)
- Sequential: version-bump → lint/type-check → tests → build (on PR)
- Release job runs only on push to main
- Version bump reads PR labels: `version:major`, `version:minor`, `version:patch`
- Compare PR version vs main version to avoid duplicate bumps
- Use `npm version $NEW_VERSION --no-git-tag-version` for package.json updates

## Requirements

### Functional
- Trigger on push to main and pull requests
- Run ESLint with flat config
- Run TypeScript type checking
- Run Vitest tests
- Build production bundle
- **Version bump on PR** - read labels and update package.json
- **Create release on push to main** - tag and GitHub release

### Non-Functional
- Cache npm dependencies
- Fail fast on errors
- Complete in < 5 minutes
- Clear job names for status checks
- Idempotent version bumps (skip if already bumped)

## Architecture

```yaml
# On PR: version-bump → lint/type-check (parallel) → test → build
# On push to main: release only

jobs:
  version-bump:    # PR only - reads labels, bumps package.json
    if: github.event_name == 'pull_request'
    ...
  lint:            # Parallel group 1 (needs version-bump on PR)
    needs: [version-bump]
    ...
  type-check:      # Parallel group 1 (needs version-bump on PR)
    needs: [version-bump]
    ...
  test:            # Depends on lint + type-check
    needs: [lint, type-check]
    ...
  build:           # Depends on test
    needs: [test]
    ...
  release:         # Push to main only
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    ...
```

## Related Code Files

**Files to create:**
- `.github/workflows/ci.yml` - CI workflow

**Dependencies:**
- Phase 01 must be complete (test script exists)
- Version labels must be created in GitHub repo settings

## Implementation Steps

### Step 1: Create workflow directory

```bash
mkdir -p .github/workflows
```

### Step 2: Create ci.yml

```yaml
name: CI Pipeline

on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, labeled, unlabeled]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: read

jobs:
  # Job 1: Calculate and commit version bump (only on PR)
  version-bump:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    if: github.event_name == 'pull_request'
    outputs:
      new_version: ${{ steps.compute-version.outputs.new_version }}
      version_bumped: ${{ steps.compute-version.outputs.version_bumped }}
    steps:
      - name: Checkout PR branch
        uses: actions/checkout@v4
        with:
          ref: ${{ github.head_ref }}
          fetch-depth: 0
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Get PR labels
        id: get-labels
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          PR_NUMBER="${{ github.event.pull_request.number }}"
          echo "PR Number: $PR_NUMBER"

          # Get labels from event payload first (more reliable)
          EVENT_LABELS='${{ toJson(github.event.pull_request.labels.*.name) }}'
          echo "Labels from event: $EVENT_LABELS"

          # Fallback to gh CLI if event labels empty
          if [ "$EVENT_LABELS" = "[]" ] || [ -z "$EVENT_LABELS" ]; then
            LABELS=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' 2>&1) || true
            echo "Labels from gh CLI: $LABELS"
          else
            LABELS="$EVENT_LABELS"
          fi

          if echo "$LABELS" | grep -q "version:major"; then
            echo "bump_type=major" >> $GITHUB_OUTPUT
            echo "Detected: major"
          elif echo "$LABELS" | grep -q "version:minor"; then
            echo "bump_type=minor" >> $GITHUB_OUTPUT
            echo "Detected: minor"
          elif echo "$LABELS" | grep -q "version:patch"; then
            echo "bump_type=patch" >> $GITHUB_OUTPUT
            echo "Detected: patch"
          else
            echo "bump_type=none" >> $GITHUB_OUTPUT
            echo "Detected: none"
          fi

      - name: Get main branch version
        id: main-version
        run: |
          # Fetch main branch version from remote
          MAIN_VERSION=$(git show origin/main:package.json 2>/dev/null | grep '"version"' | sed 's/.*"version": "\([^"]*\)".*/\1/' || echo "0.0.0")
          echo "main_version=$MAIN_VERSION" >> $GITHUB_OUTPUT
          echo "Main branch version: $MAIN_VERSION"

      - name: Compute new version
        id: compute-version
        run: |
          BUMP_TYPE="${{ steps.get-labels.outputs.bump_type }}"
          MAIN_VERSION="${{ steps.main-version.outputs.main_version }}"

          # Get current PR version
          PR_VERSION=$(grep '"version"' package.json | sed 's/.*"version": "\([^"]*\)".*/\1/')
          echo "PR version: $PR_VERSION"
          echo "Main version: $MAIN_VERSION"

          # No version label - skip bump
          if [ "$BUMP_TYPE" = "none" ] || [ -z "$BUMP_TYPE" ]; then
            echo "new_version=$PR_VERSION" >> $GITHUB_OUTPUT
            echo "version_bumped=false" >> $GITHUB_OUTPUT
            echo "No version label found, skipping bump"
            exit 0
          fi

          # Compare versions: if PR version > main version, version already bumped
          version_gt() {
            test "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" && test "$1" != "$2"
          }

          if version_gt "$PR_VERSION" "$MAIN_VERSION"; then
            echo "new_version=$PR_VERSION" >> $GITHUB_OUTPUT
            echo "version_bumped=false" >> $GITHUB_OUTPUT
            echo "PR version ($PR_VERSION) > main version ($MAIN_VERSION) - already bumped, skipping"
            exit 0
          fi

          # Validate version format
          if ! echo "$MAIN_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "::error::Invalid main version format: $MAIN_VERSION"
            exit 1
          fi

          # Calculate new version from main branch version
          MAJOR=$(echo "$MAIN_VERSION" | cut -d. -f1)
          MINOR=$(echo "$MAIN_VERSION" | cut -d. -f2)
          PATCH=$(echo "$MAIN_VERSION" | cut -d. -f3)

          case "$BUMP_TYPE" in
            major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
            minor) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
            patch) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
          esac

          # Check if PR already has the target version
          if [ "$PR_VERSION" = "$NEW_VERSION" ]; then
            echo "new_version=$PR_VERSION" >> $GITHUB_OUTPUT
            echo "version_bumped=false" >> $GITHUB_OUTPUT
            echo "PR already has target version $NEW_VERSION, skipping bump"
            exit 0
          fi

          echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
          echo "current_version=$PR_VERSION" >> $GITHUB_OUTPUT
          echo "version_bumped=true" >> $GITHUB_OUTPUT
          echo "Version will bump: $PR_VERSION -> $NEW_VERSION ($BUMP_TYPE based on main $MAIN_VERSION)"

      - name: Setup Node.js
        if: steps.compute-version.outputs.version_bumped == 'true'
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Update package.json
        if: steps.compute-version.outputs.version_bumped == 'true'
        run: |
          NEW_VERSION="${{ steps.compute-version.outputs.new_version }}"
          npm version "$NEW_VERSION" --no-git-tag-version

      - name: Commit version bump to PR
        if: steps.compute-version.outputs.version_bumped == 'true'
        run: |
          NEW_VERSION="${{ steps.compute-version.outputs.new_version }}"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          if ! git diff --quiet package.json package-lock.json; then
            git add package.json package-lock.json
            git commit -m "chore: bump version to $NEW_VERSION"
            git push origin ${{ github.head_ref }}
          else
            echo "package.json already has version $NEW_VERSION"
          fi

  # Job 2: Lint (parallel with type-check)
  lint:
    name: Lint
    runs-on: ubuntu-latest
    timeout-minutes: 5
    needs: [version-bump]
    if: always() && (needs.version-bump.result == 'success' || needs.version-bump.result == 'skipped')
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event_name == 'pull_request' && github.head_ref || github.ref }}

      - name: Pull latest changes
        if: github.event_name == 'pull_request'
        run: git pull origin ${{ github.head_ref }} || true

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run ESLint
        run: npm run lint

  # Job 3: Type Check (parallel with lint)
  type-check:
    name: Type Check
    runs-on: ubuntu-latest
    timeout-minutes: 5
    needs: [version-bump]
    if: always() && (needs.version-bump.result == 'success' || needs.version-bump.result == 'skipped')
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event_name == 'pull_request' && github.head_ref || github.ref }}

      - name: Pull latest changes
        if: github.event_name == 'pull_request'
        run: git pull origin ${{ github.head_ref }} || true

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run TypeScript compiler
        run: npm run type-check

  # Job 4: Test (depends on lint + type-check)
  test:
    name: Test
    runs-on: ubuntu-latest
    timeout-minutes: 10
    needs: [lint, type-check]
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event_name == 'pull_request' && github.head_ref || github.ref }}

      - name: Pull latest changes
        if: github.event_name == 'pull_request'
        run: git pull origin ${{ github.head_ref }} || true

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm run test

  # Job 5: Build (depends on test)
  build:
    name: Build
    runs-on: ubuntu-latest
    timeout-minutes: 10
    needs: [test]
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event_name == 'pull_request' && github.head_ref || github.ref }}

      - name: Pull latest changes
        if: github.event_name == 'pull_request'
        run: git pull origin ${{ github.head_ref }} || true

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Build production bundle
        run: npm run build

  # Job 6: Create release (only on push to main)
  release:
    name: Release
    runs-on: ubuntu-latest
    timeout-minutes: 5
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get version
        id: get-version
        run: |
          VERSION=$(grep '"version"' package.json | sed 's/.*"version": "\([^"]*\)".*/\1/')
          echo "version=$VERSION" >> $GITHUB_OUTPUT
          echo "tag=v$VERSION" >> $GITHUB_OUTPUT

      - name: Check if tag exists
        id: check-tag
        run: |
          TAG="${{ steps.get-version.outputs.tag }}"
          if git rev-parse "$TAG" >/dev/null 2>&1; then
            echo "exists=true" >> $GITHUB_OUTPUT
            echo "Tag $TAG already exists, skipping release"
          else
            echo "exists=false" >> $GITHUB_OUTPUT
            echo "Tag $TAG does not exist, will create release"
          fi

      - name: Create tag
        if: steps.check-tag.outputs.exists == 'false'
        run: |
          TAG="${{ steps.get-version.outputs.tag }}"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git tag -a "$TAG" -m "Release $TAG"
          git push origin "$TAG"

      - name: Create GitHub Release
        if: steps.check-tag.outputs.exists == 'false'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          VERSION="${{ steps.get-version.outputs.version }}"
          TAG="${{ steps.get-version.outputs.tag }}"
          gh release create "$TAG" \
            --title "$TAG" \
            --notes "## What's Changed

          Version $VERSION released.

          **Full Changelog**: https://github.com/${{ github.repository }}/commits/$TAG" \
            --latest

      - name: Write job summary
        if: steps.check-tag.outputs.exists == 'false'
        run: |
          echo "## Release Created" >> $GITHUB_STEP_SUMMARY
          echo "- **Version:** ${{ steps.get-version.outputs.version }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Tag:** ${{ steps.get-version.outputs.tag }}" >> $GITHUB_STEP_SUMMARY

      - name: Skip summary
        if: steps.check-tag.outputs.exists == 'true'
        run: |
          echo "## Release Skipped" >> $GITHUB_STEP_SUMMARY
          echo "Tag ${{ steps.get-version.outputs.tag }} already exists" >> $GITHUB_STEP_SUMMARY
```

### Step 3: Create version labels in GitHub

Create these labels in GitHub repository settings:
- `version:major` - Major version bump (breaking changes)
- `version:minor` - Minor version bump (new features)
- `version:patch` - Patch version bump (bug fixes)

### Step 4: Test workflow

1. Create PR with `version:patch` label
2. Verify version bump commits
3. Merge PR to main
4. Verify release created

## Todo List

- [x] Create .github/workflows directory
- [x] Create ci.yml workflow file
- [x] Create version labels in GitHub repo settings
- [x] Test version bump on PR
- [x] Test release creation on merge to main
- [x] Verify all jobs run in correct order

## Success Criteria

- [x] Workflow triggers on PR and push to main
- [x] Version bump job reads PR labels correctly
- [x] Version bump commits to PR branch
- [x] Lint and type-check run in parallel after version bump
- [x] Test job runs after lint/type-check pass
- [x] Build job runs after tests pass
- [x] Release job creates tag and GitHub release on push to main
- [x] npm cache working (faster subsequent runs)
- [x] Failed job stops pipeline

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ESLint 9 flat config issues | Low | Low | Already working locally |
| Long build times | Low | Low | Caching enabled |
| Test failures | Medium | Low | Fix tests before merge |
| Version label missing | Medium | Low | Skip bump if no label |
| Concurrent PR version conflicts | Low | Medium | Compare vs main version |
| Package-lock.json out of sync | Low | Low | npm version updates both files |

## Security Considerations

- Uses `GITHUB_TOKEN` (automatic, limited scope)
- No external secrets required
- `contents: write` permission for version commits and releases
- `pull-requests: read` permission for label access
- Uses official GitHub Actions only
- Concurrency prevents race conditions

## Next Steps

After this phase:
- Phase 03: Write unit tests for utilities
- Consider adding: coverage reports, E2E tests, deployment
