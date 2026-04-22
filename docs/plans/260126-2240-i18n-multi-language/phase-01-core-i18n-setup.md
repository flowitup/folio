# Phase 01: Core i18n Setup with next-intl

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: None (first phase)
- **Docs**: [next-intl App Router docs](https://next-intl-docs.vercel.app/docs/getting-started/app-router)

## Overview

- **Priority**: High
- **Status**: pending
- **Effort**: 45m

Install `next-intl` and configure core i18n infrastructure including config files, message files, and middleware integration.

## Key Insights

- next-intl requires specific setup for Next.js App Router
- Middleware handles locale detection and redirection
- Must integrate with existing auth middleware without conflicts
- Cookie-based persistence requires `NEXT_LOCALE` cookie

## Requirements

### Functional
- Install and configure next-intl
- Create i18n config with supported locales (en, vi, fr)
- Set up message JSON files for all 3 languages
- Integrate i18n middleware with existing auth middleware

### Non-Functional
- Maintain auth middleware functionality
- No performance degradation on page load
- Type-safe translations

## Architecture

```
src/
├── i18n/
│   ├── config.ts           # Locale config + routing
│   └── request.ts          # Server request config
├── messages/
│   ├── en.json             # English (default)
│   ├── vi.json             # Vietnamese
│   └── fr.json             # French
└── middleware.ts           # Combined auth + i18n
```

### Middleware Flow
```
Request → i18n (locale detect) → Auth (token check) → Response
```

## Related Code Files

### Files to Create
- `src/i18n/config.ts`
- `src/i18n/request.ts`
- `src/messages/en.json`
- `src/messages/vi.json`
- `src/messages/fr.json`

### Files to Modify
- `package.json` - Add next-intl dependency
- `next.config.ts` - Add next-intl plugin
- `src/middleware.ts` - Integrate i18n middleware

## Implementation Steps

1. **Install next-intl**
   ```bash
   npm install next-intl
   ```

2. **Create i18n config** (`src/i18n/config.ts`)
   ```typescript
   export const locales = ['en', 'vi', 'fr'] as const;
   export type Locale = (typeof locales)[number];
   export const defaultLocale: Locale = 'en';
   ```

3. **Create request config** (`src/i18n/request.ts`)
   ```typescript
   import { getRequestConfig } from 'next-intl/server';
   import { locales, defaultLocale } from './config';

   export default getRequestConfig(async ({ requestLocale }) => {
     let locale = await requestLocale;
     if (!locale || !locales.includes(locale as any)) {
       locale = defaultLocale;
     }
     return {
       locale,
       messages: (await import(`../messages/${locale}.json`)).default
     };
   });
   ```

4. **Create initial message files** with basic structure:
   - `src/messages/en.json`
   - `src/messages/vi.json`
   - `src/messages/fr.json`

5. **Update next.config.ts** with next-intl plugin
   ```typescript
   import createNextIntlPlugin from 'next-intl/plugin';
   const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');
   ```

6. **Update middleware.ts** to chain i18n with auth
   - Use `createMiddleware` from next-intl
   - Preserve existing auth logic
   - Handle locale-prefixed paths

## Todo List

- [ ] Install next-intl package
- [ ] Create src/i18n/config.ts
- [ ] Create src/i18n/request.ts
- [ ] Create src/messages/en.json with initial structure
- [ ] Create src/messages/vi.json
- [ ] Create src/messages/fr.json
- [ ] Update next.config.ts with plugin
- [ ] Update middleware.ts with i18n integration
- [ ] Verify middleware chain works

## Success Criteria

- [ ] `npm run build` passes
- [ ] Middleware redirects `/` to `/en/`
- [ ] Locale cookie (`NEXT_LOCALE`) is set
- [ ] Auth middleware still protects routes
- [ ] No TypeScript errors

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Middleware conflict | High | Test auth flow after integration |
| Build errors | Medium | Follow next-intl docs exactly |
| Cookie not persisting | Low | Verify cookie settings |

## Security Considerations

- Locale parameter validated against allowed list
- No user input passed to file imports
- Cookie httpOnly not needed (locale is not sensitive)

## Next Steps

After completing this phase, proceed to [Phase 02: App Router Restructure](./phase-02-app-router-restructure.md) to reorganize app directory with `[locale]` segment.
