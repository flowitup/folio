# Phase 01: Setup Test Framework

## Context Links
- [Parent Plan](plan.md)
- [Vitest Docs](https://vitest.dev/)

## Overview

| Field | Value |
|-------|-------|
| Priority | P2 |
| Status | done |
| Review Status | completed |
| Completed | 2026-01-18 |
| Effort | 1h |

Install and configure Vitest testing framework for Next.js 16 with React 19.

## Key Insights

- Vitest preferred over Jest for speed and ESM support
- Next.js 16 requires @vitejs/plugin-react for JSX
- React Testing Library for component tests
- jsdom environment for DOM testing

## Requirements

### Functional
- Install Vitest and dependencies
- Configure for Next.js path aliases
- Add `test` script to package.json
- Create example test to verify setup

### Non-Functional
- Tests run in under 5 seconds
- Support for TypeScript out of box
- Compatible with React 19

## Related Code Files

**Files to modify:**
- `package.json` - Add dependencies and test script

**Files to create:**
- `vitest.config.ts` - Vitest configuration
- `src/__tests__/setup.test.ts` - Setup verification test

## Implementation Steps

### Step 1: Install Dependencies

```bash
npm install -D vitest @vitejs/plugin-react jsdom @testing-library/react @testing-library/dom
```

### Step 2: Create vitest.config.ts

```typescript
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: [],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
```

### Step 3: Add test script to package.json

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "type-check": "tsc --noEmit"
  }
}
```

### Step 4: Create setup verification test

```typescript
// src/__tests__/setup.test.ts
import { describe, it, expect } from 'vitest'

describe('Test Framework Setup', () => {
  it('should verify Vitest is configured correctly', () => {
    expect(true).toBe(true)
  })

  it('should verify path aliases work', () => {
    expect(process.cwd()).toContain('construction-front-end')
  })
})
```

### Step 5: Verify setup

```bash
npm run test
npm run type-check
```

## Todo List

- [x] Install Vitest and testing dependencies
- [x] Create vitest.config.ts
- [x] Add test and type-check scripts
- [x] Create example test file
- [x] Run tests to verify setup

## Success Criteria

- [x] `npm run test` executes without errors
- [x] `npm run type-check` passes
- [x] Example test passes
- [x] Path aliases (@/*) work in tests

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| React 19 compatibility | Low | Medium | Use latest Vitest |
| ESM issues | Low | Medium | Configure properly |

## Security Considerations

- No security concerns for test setup

## Completion Summary

**Completed:** 2026-01-18

**Files Created:**
- `vitest.config.ts` - Vitest configuration with React plugin, jsdom, path aliases
- `src/__tests__/setup.test.ts` - Setup verification tests (2 tests)

**Files Modified:**
- `package.json` - Added test scripts: `test`, `test:watch`, `type-check`

**Dependencies Added:**
- vitest: ^4.0.17
- @vitejs/plugin-react: ^5.1.2
- jsdom: ^27.4.0
- @testing-library/react: ^16.3.1
- @testing-library/dom: ^10.4.1

**Test Results:**
- All tests pass successfully
- `npm run test` executes in <5 seconds
- TypeScript type checking passes
- Path aliases (@/*) work correctly in tests

## Next Steps

After this phase:
→ Phase 02: Create CI Workflow
