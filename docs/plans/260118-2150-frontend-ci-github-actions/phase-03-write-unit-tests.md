# Phase 03: Write Unit Tests

## Context Links
- [Parent Plan](plan.md)
- [Phase 02: Create CI Workflow](phase-02-create-ci-workflow.md)
- [Vitest Docs](https://vitest.dev/)
- [Testing Library Docs](https://testing-library.com/docs/react-testing-library/intro/)

## Overview

| Field | Value |
|-------|-------|
| Date | 2026-01-18 |
| Priority | P2 |
| Status | completed |
| Review Status | approved |
| Effort | 1h |

Write unit tests for frontend utilities to ensure CI pipeline has meaningful tests to run. Focus on testable utility functions: API client, environment config, type guards.

## Key Insights

- Existing test file: `src/__tests__/setup.test.ts` (framework verification only)
- Testable utilities identified:
  - `src/lib/api/http.ts` - ApiError class, http wrapper (needs mocking)
  - `src/lib/config/env.ts` - getEnvVar function, isDevelopment/isProduction flags
  - `src/lib/auth/types.ts` - Type definitions (create type guard tests)
- Test convention: `*.test.ts` in `__tests__/` directory
- Vitest 4 with jsdom environment already configured

## Requirements

### Functional
- Write tests for ApiError class construction and properties
- Write tests for environment variable handling
- Write tests for type guards (if needed)
- Create utility formatters for demonstration if none exist
- Ensure all tests pass before CI implementation

### Non-Functional
- Tests run in < 10 seconds total
- Clear test descriptions
- Proper mocking for external dependencies (fetch, process.env)
- No flaky tests

## Architecture

```
src/
├── __tests__/
│   ├── setup.test.ts          # Existing - framework verification
│   ├── api-error.test.ts      # NEW - ApiError class tests
│   ├── env-config.test.ts     # NEW - Environment config tests
│   └── formatters.test.ts     # NEW - Utility formatter tests
├── lib/
│   ├── api/
│   │   └── http.ts            # ApiError, http wrapper
│   ├── config/
│   │   └── env.ts             # Environment config
│   └── utils/
│       └── formatters.ts      # NEW - Create if needed
```

## Related Code Files

**Files to test:**
- `src/lib/api/http.ts` - ApiError class
- `src/lib/config/env.ts` - Environment utilities

**Files to create:**
- `src/__tests__/api-error.test.ts` - ApiError tests
- `src/__tests__/env-config.test.ts` - Environment tests
- `src/lib/utils/formatters.ts` - Utility formatters (if needed)
- `src/__tests__/formatters.test.ts` - Formatter tests

**Dependencies:**
- Phase 01 complete (Vitest configured)

## Implementation Steps

### Step 1: Create ApiError tests

```typescript
// src/__tests__/api-error.test.ts
import { describe, it, expect } from 'vitest'
import { ApiError } from '@/lib/api/http'

describe('ApiError', () => {
  it('should create error with message and status', () => {
    const error = new ApiError('Not Found', 404)

    expect(error.message).toBe('Not Found')
    expect(error.status).toBe(404)
    expect(error.name).toBe('ApiError')
    expect(error.data).toBeUndefined()
  })

  it('should create error with additional data', () => {
    const errorData = { field: 'email', reason: 'invalid' }
    const error = new ApiError('Validation Error', 400, errorData)

    expect(error.status).toBe(400)
    expect(error.data).toEqual(errorData)
  })

  it('should be instanceof Error', () => {
    const error = new ApiError('Server Error', 500)

    expect(error).toBeInstanceOf(Error)
    expect(error).toBeInstanceOf(ApiError)
  })

  it('should have correct error name for stack traces', () => {
    const error = new ApiError('Unauthorized', 401)

    expect(error.name).toBe('ApiError')
    expect(error.stack).toContain('ApiError')
  })
})
```

### Step 2: Create environment config tests

```typescript
// src/__tests__/env-config.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

describe('Environment Config', () => {
  const originalEnv = process.env

  beforeEach(() => {
    vi.resetModules()
    process.env = { ...originalEnv }
  })

  afterEach(() => {
    process.env = originalEnv
  })

  describe('isDevelopment', () => {
    it('should return true when NODE_ENV is development', async () => {
      process.env.NODE_ENV = 'development'
      process.env.NEXT_PUBLIC_API_BASE_URL = 'http://localhost:8000'

      const { isDevelopment } = await import('@/lib/config/env')
      expect(isDevelopment).toBe(true)
    })

    it('should return false when NODE_ENV is production', async () => {
      process.env.NODE_ENV = 'production'
      process.env.NEXT_PUBLIC_API_BASE_URL = 'https://api.example.com'

      const { isDevelopment } = await import('@/lib/config/env')
      expect(isDevelopment).toBe(false)
    })
  })

  describe('isProduction', () => {
    it('should return true when NODE_ENV is production', async () => {
      process.env.NODE_ENV = 'production'
      process.env.NEXT_PUBLIC_API_BASE_URL = 'https://api.example.com'

      const { isProduction } = await import('@/lib/config/env')
      expect(isProduction).toBe(true)
    })

    it('should return false when NODE_ENV is development', async () => {
      process.env.NODE_ENV = 'development'
      process.env.NEXT_PUBLIC_API_BASE_URL = 'http://localhost:8000'

      const { isProduction } = await import('@/lib/config/env')
      expect(isProduction).toBe(false)
    })
  })

  describe('env.apiBaseUrl', () => {
    it('should read NEXT_PUBLIC_API_BASE_URL', async () => {
      process.env.NEXT_PUBLIC_API_BASE_URL = 'https://api.test.com'

      const { env } = await import('@/lib/config/env')
      expect(env.apiBaseUrl).toBe('https://api.test.com')
    })

    it('should throw when required env var is missing', async () => {
      delete process.env.NEXT_PUBLIC_API_BASE_URL

      await expect(import('@/lib/config/env')).rejects.toThrow(
        'Missing required environment variable: NEXT_PUBLIC_API_BASE_URL'
      )
    })
  })
})
```

### Step 3: Create utility formatters (if not existing)

```typescript
// src/lib/utils/formatters.ts
/**
 * Utility formatting functions
 */

/**
 * Format a number as currency (USD)
 */
export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount)
}

/**
 * Format a date as a readable string
 */
export function formatDate(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(d)
}

/**
 * Truncate string with ellipsis
 */
export function truncate(str: string, maxLength: number): string {
  if (str.length <= maxLength) return str
  return str.slice(0, maxLength - 3) + '...'
}

/**
 * Slugify a string for URLs
 */
export function slugify(str: string): string {
  return str
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

/**
 * Check if string is valid email format
 */
export function isValidEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return emailRegex.test(email)
}
```

### Step 4: Create formatter tests

```typescript
// src/__tests__/formatters.test.ts
import { describe, it, expect } from 'vitest'
import {
  formatCurrency,
  formatDate,
  truncate,
  slugify,
  isValidEmail,
} from '@/lib/utils/formatters'

describe('formatCurrency', () => {
  it('should format positive numbers', () => {
    expect(formatCurrency(1234.56)).toBe('$1,234.56')
  })

  it('should format zero', () => {
    expect(formatCurrency(0)).toBe('$0.00')
  })

  it('should format negative numbers', () => {
    expect(formatCurrency(-500)).toBe('-$500.00')
  })

  it('should handle large numbers', () => {
    expect(formatCurrency(1000000)).toBe('$1,000,000.00')
  })
})

describe('formatDate', () => {
  it('should format Date object', () => {
    const date = new Date('2026-01-18')
    expect(formatDate(date)).toBe('Jan 18, 2026')
  })

  it('should format ISO string', () => {
    expect(formatDate('2026-12-25')).toBe('Dec 25, 2026')
  })
})

describe('truncate', () => {
  it('should not truncate short strings', () => {
    expect(truncate('Hello', 10)).toBe('Hello')
  })

  it('should truncate long strings with ellipsis', () => {
    expect(truncate('Hello World', 8)).toBe('Hello...')
  })

  it('should handle exact length', () => {
    expect(truncate('Hello', 5)).toBe('Hello')
  })

  it('should handle empty string', () => {
    expect(truncate('', 10)).toBe('')
  })
})

describe('slugify', () => {
  it('should convert to lowercase', () => {
    expect(slugify('Hello World')).toBe('hello-world')
  })

  it('should replace spaces with hyphens', () => {
    expect(slugify('my blog post')).toBe('my-blog-post')
  })

  it('should remove special characters', () => {
    expect(slugify('Hello! World?')).toBe('hello-world')
  })

  it('should trim whitespace', () => {
    expect(slugify('  hello  ')).toBe('hello')
  })

  it('should handle multiple spaces', () => {
    expect(slugify('hello   world')).toBe('hello-world')
  })
})

describe('isValidEmail', () => {
  it('should validate correct email', () => {
    expect(isValidEmail('test@example.com')).toBe(true)
  })

  it('should validate email with subdomain', () => {
    expect(isValidEmail('user@mail.example.com')).toBe(true)
  })

  it('should reject email without @', () => {
    expect(isValidEmail('invalid.email')).toBe(false)
  })

  it('should reject email without domain', () => {
    expect(isValidEmail('test@')).toBe(false)
  })

  it('should reject email with spaces', () => {
    expect(isValidEmail('test @example.com')).toBe(false)
  })

  it('should reject empty string', () => {
    expect(isValidEmail('')).toBe(false)
  })
})
```

### Step 5: Update vitest.config.ts (if needed)

Ensure coverage is configured for CI reporting:

```typescript
// vitest.config.ts (additions)
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: [],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        '.next/',
        '**/*.d.ts',
        '**/*.config.*',
      ],
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
```

### Step 6: Run and verify tests

```bash
cd construction-front-end
npm run test
```

Expected output:
```
 ✓ src/__tests__/setup.test.ts (2 tests)
 ✓ src/__tests__/api-error.test.ts (4 tests)
 ✓ src/__tests__/env-config.test.ts (5 tests)
 ✓ src/__tests__/formatters.test.ts (14 tests)

 Test Files  4 passed (4)
      Tests  25 passed (25)
```

## Todo List

- [x] Create `src/__tests__/api-error.test.ts`
- [x] Create `src/__tests__/env-config.test.ts`
- [x] Create `src/lib/utils/formatters.ts` (utility functions)
- [x] Create `src/__tests__/formatters.test.ts`
- [x] Run all tests and verify passing
- [x] Create `src/__tests__/vitest.setup.ts` (test env defaults)
- [ ] Update vitest.config.ts with coverage (optional)

## Success Criteria

- [x] All unit tests pass locally (34 tests in 396ms)
- [x] Test coverage includes ApiError class (5 tests)
- [x] Test coverage includes environment config (6 tests)
- [x] Test coverage includes utility formatters (21 tests)
- [x] Tests run in < 10 seconds (396ms total)
- [x] No flaky or intermittent failures
- [ ] CI pipeline runs tests successfully

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Env module caching | Medium | Low | Use `vi.resetModules()` |
| Fetch mocking complexity | Low | Medium | Test ApiError class only, not http wrapper |
| Date formatting locale | Low | Low | Use specific locale in tests |
| Path alias issues | Low | Low | Already configured in Phase 01 |

## Security Considerations

- No real API calls in tests (mocked)
- No real credentials or secrets
- Environment variables isolated per test
- Tests run in sandboxed jsdom environment

## Next Steps

After this phase:
- Plan complete
- Push changes and verify CI runs all tests
- Consider adding: coverage thresholds, E2E tests, component tests
