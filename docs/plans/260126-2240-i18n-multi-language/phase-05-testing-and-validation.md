# Phase 05: Testing and Validation

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 04](./phase-04-language-switcher-component.md)
- **Docs**: [Vitest Testing](https://vitest.dev/guide/)

## Overview

- **Priority**: Medium
- **Status**: pending
- **Effort**: 30m

Validate the i18n implementation through manual testing, automated tests, and final verification of all requirements.

## Key Insights

- Test all 3 locales (en, vi, fr) for each page
- Verify SSR renders correct locale
- Test middleware locale detection
- Ensure auth flow works with locale prefixes

## Requirements

### Functional
- All pages render correctly in all 3 locales
- Language switcher works on all pages
- Auth redirects include locale prefix
- Cookie persistence works across sessions

### Non-Functional
- No console errors or warnings
- Build passes without errors
- Performance not degraded

## Architecture

### Test Coverage Areas

```
1. Unit Tests
   - i18n config validation
   - Locale detection logic

2. Integration Tests
   - Middleware routing
   - Auth + i18n middleware chain

3. E2E/Manual Tests
   - Full user flow per locale
   - Language switching journey
```

## Related Code Files

### Files to Create
- `src/__tests__/i18n-config.test.ts`
- `src/__tests__/i18n-middleware.test.ts`

### Files to Verify
- All page files in `src/app/[locale]/`
- All components using translations
- `src/middleware.ts`

## Implementation Steps

1. **Create i18n config tests**
   ```typescript
   // src/__tests__/i18n-config.test.ts
   import { describe, it, expect } from 'vitest';
   import { locales, defaultLocale } from '@/i18n/config';

   describe('i18n config', () => {
     it('has correct default locale', () => {
       expect(defaultLocale).toBe('en');
     });

     it('supports all required locales', () => {
       expect(locales).toContain('en');
       expect(locales).toContain('vi');
       expect(locales).toContain('fr');
     });
   });
   ```

2. **Manual Testing Checklist**

   **For each locale (en, vi, fr):**

   | Page | URL | Test |
   |------|-----|------|
   | Home | `/{locale}` | Renders landing page |
   | Login | `/{locale}/login` | Form labels translated |
   | Dashboard | `/{locale}/dashboard` | All text translated |
   | Projects | `/{locale}/projects` | Navigation translated |
   | Settings | `/{locale}/settings` | Section titles translated |

3. **Auth Flow Tests**

   | Scenario | Expected |
   |----------|----------|
   | Unauthenticated → /en/dashboard | Redirect to /en/login |
   | Authenticated → /fr/login | Redirect to /fr/dashboard |
   | Login success from /vi/login | Redirect to /vi/dashboard |

4. **Middleware Tests**

   | Request | Expected Response |
   |---------|-------------------|
   | GET / | Redirect to /en/ |
   | GET /dashboard | Redirect to /en/dashboard |
   | GET /en/dashboard (no auth) | Redirect to /en/login |
   | Cookie NEXT_LOCALE=fr + GET / | Redirect to /fr/ |

5. **Build Verification**
   ```bash
   npm run type-check
   npm run lint
   npm run build
   ```

6. **Performance Check**
   - Compare page load times before/after
   - Check bundle size increase from next-intl

## Todo List

- [ ] Create i18n-config.test.ts
- [ ] Run manual tests for /en pages
- [ ] Run manual tests for /vi pages
- [ ] Run manual tests for /fr pages
- [ ] Test auth flow with locale prefixes
- [ ] Test language switcher on all pages
- [ ] Test cookie persistence (close/reopen browser)
- [ ] Run npm run type-check
- [ ] Run npm run lint
- [ ] Run npm run build
- [ ] Run npm run test
- [ ] Document any issues found

## Success Criteria

- [ ] All manual test cases pass
- [ ] No TypeScript errors
- [ ] No ESLint errors
- [ ] Build completes successfully
- [ ] All unit tests pass
- [ ] No console errors in browser
- [ ] Cookie persists locale preference

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing translations | Medium | Check console for warnings |
| Broken auth flow | High | Prioritize auth tests |
| Build failure | High | Fix errors before merge |

## Security Considerations

- Verify locale parameter cannot be exploited
- Confirm auth protection still works
- Check for any exposed sensitive data

## Final Verification Checklist

Before marking implementation complete:

- [ ] All phases completed
- [ ] All tests passing
- [ ] Code reviewed
- [ ] No console errors
- [ ] Translations accurate
- [ ] Accessible (keyboard, screen reader)
- [ ] Responsive (mobile, tablet, desktop)
- [ ] Documentation updated

## Next Steps

After validation passes:
1. Create PR for code review
2. Deploy to staging environment
3. QA verification
4. Merge to main branch
