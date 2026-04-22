# Phase 02: App Router Restructure with [locale] Segment

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 01](./phase-01-core-i18n-setup.md)
- **Docs**: [next-intl App Router Setup](https://next-intl-docs.vercel.app/docs/getting-started/app-router/with-i18n-routing)

## Overview

- **Priority**: High
- **Status**: pending
- **Effort**: 45m

Restructure the app directory to use `[locale]` dynamic segment for URL-based locale routing. All pages will be nested under `app/[locale]/`.

## Key Insights

- Next.js App Router uses folder-based routing
- `[locale]` segment captures locale from URL
- Root layout must wrap with `NextIntlClientProvider`
- Existing `(app)` route group preserved inside `[locale]`

## Requirements

### Functional
- All routes prefixed with locale: `/en/*`, `/vi/*`, `/fr/*`
- Root redirect from `/` to `/en/`
- Preserve existing route group `(app)` for protected pages
- Pass locale to html lang attribute

### Non-Functional
- Maintain SEO with correct lang attribute
- No broken links after restructure
- All existing pages accessible at new paths

## Architecture

### Current Structure
```
src/app/
├── layout.tsx
├── page.tsx
├── login/page.tsx
├── unauthorized/page.tsx
└── (app)/
    ├── layout.tsx
    ├── dashboard/page.tsx
    ├── projects/page.tsx
    └── settings/page.tsx
```

### Target Structure
```
src/app/
├── [locale]/
│   ├── layout.tsx              # Root layout with NextIntlClientProvider
│   ├── page.tsx                # Landing page
│   ├── login/page.tsx
│   ├── unauthorized/page.tsx
│   └── (app)/
│       ├── layout.tsx          # Protected layout (unchanged logic)
│       ├── dashboard/page.tsx
│       ├── projects/page.tsx
│       └── settings/page.tsx
└── globals.css                 # Keep at root
```

## Related Code Files

### Files to Move/Rename
- `src/app/layout.tsx` → `src/app/[locale]/layout.tsx`
- `src/app/page.tsx` → `src/app/[locale]/page.tsx`
- `src/app/login/page.tsx` → `src/app/[locale]/login/page.tsx`
- `src/app/unauthorized/page.tsx` → `src/app/[locale]/unauthorized/page.tsx`
- `src/app/(app)/*` → `src/app/[locale]/(app)/*`

### Files to Modify
- `src/app/[locale]/layout.tsx` - Add NextIntlClientProvider, dynamic lang
- `src/app/[locale]/(app)/layout.tsx` - Update redirect paths
- `src/middleware.ts` - Handle locale-prefixed routes

## Implementation Steps

1. **Create [locale] directory**
   ```bash
   mkdir -p src/app/[locale]
   ```

2. **Move all app content** into `[locale]`
   - Move layout.tsx, page.tsx
   - Move login/, unauthorized/
   - Move (app)/ route group

3. **Update root layout** (`src/app/[locale]/layout.tsx`)
   ```typescript
   import { NextIntlClientProvider } from 'next-intl';
   import { getMessages, getLocale } from 'next-intl/server';

   export default async function RootLayout({
     children,
   }: {
     children: React.ReactNode;
   }) {
     const locale = await getLocale();
     const messages = await getMessages();

     return (
       <html lang={locale}>
         <body>
           <NextIntlClientProvider messages={messages}>
             {/* existing providers */}
             {children}
           </NextIntlClientProvider>
         </body>
       </html>
     );
   }
   ```

4. **Update (app) layout** - Fix redirect paths
   ```typescript
   // Change: redirect("/login")
   // To: redirect(`/${locale}/login`)
   ```

5. **Update middleware** auth redirects to include locale
   - `/login` → `/${locale}/login`
   - `/dashboard` → `/${locale}/dashboard`

6. **Update internal links** in components
   - Use `Link` from `next-intl/navigation` or prefix with locale

## Todo List

- [ ] Create src/app/[locale] directory
- [ ] Move layout.tsx to [locale]/layout.tsx
- [ ] Move page.tsx to [locale]/page.tsx
- [ ] Move login/ to [locale]/login/
- [ ] Move unauthorized/ to [locale]/unauthorized/
- [ ] Move (app)/ to [locale]/(app)/
- [ ] Update root layout with NextIntlClientProvider
- [ ] Update (app) layout redirect paths
- [ ] Update middleware auth redirects
- [ ] Test all routes work with /en prefix

## Success Criteria

- [ ] `/en/dashboard` loads dashboard page
- [ ] `/vi/login` loads login in Vietnamese context
- [ ] `/fr/settings` loads settings page
- [ ] HTML `lang` attribute matches URL locale
- [ ] Auth redirects include locale prefix
- [ ] No 404 errors on existing functionality

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Broken internal links | High | Search and update all Link components |
| Auth redirect loops | High | Test auth flow thoroughly |
| Missing pages | Medium | Verify all pages moved correctly |

## Security Considerations

- Locale parameter validated in middleware
- Auth checks preserved in (app) layout
- No changes to auth token handling

## Next Steps

After completing this phase, proceed to [Phase 03](./phase-03-extract-translations-from-components.md) to extract hardcoded strings into translation files.
