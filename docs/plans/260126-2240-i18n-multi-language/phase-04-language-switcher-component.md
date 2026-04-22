# Phase 04: Language Switcher Component

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 03](./phase-03-extract-translations-from-components.md)
- **Docs**: [next-intl Navigation](https://next-intl-docs.vercel.app/docs/routing/navigation)

## Overview

- **Priority**: Medium
- **Status**: pending
- **Effort**: 30m

Create a language switcher component that allows users to change the app language. Integrate it into the Topbar for easy access.

## Key Insights

- Use `useRouter` and `usePathname` from `next-intl/navigation`
- Set `NEXT_LOCALE` cookie for persistence
- Display current locale with dropdown/buttons for others
- Consider showing language names in their native form

## Requirements

### Functional
- Dropdown/button group to switch between en/vi/fr
- Current language visually highlighted
- Clicking switches URL locale and sets cookie
- Preserve current page path when switching

### Non-Functional
- Accessible (keyboard navigation, ARIA labels)
- Responsive design (works on mobile)
- Smooth transition, no page flicker

## Architecture

### Component Structure
```
src/components/
└── language-switcher.tsx    # Client component
```

### Cookie Persistence
```typescript
// Set cookie on locale change
document.cookie = `NEXT_LOCALE=${locale}; path=/; max-age=31536000`;
```

### Navigation Helper
```typescript
// src/i18n/navigation.ts
import { createNavigation } from 'next-intl/navigation';
import { locales } from './config';

export const { Link, redirect, usePathname, useRouter } = createNavigation({ locales });
```

## Related Code Files

### Files to Create
- `src/components/language-switcher.tsx`
- `src/i18n/navigation.ts`

### Files to Modify
- `src/components/layout/Topbar.tsx` - Add LanguageSwitcher

## Implementation Steps

1. **Create navigation helpers** (`src/i18n/navigation.ts`)
   ```typescript
   import { createNavigation } from 'next-intl/navigation';
   import { locales, defaultLocale } from './config';

   export const { Link, redirect, usePathname, useRouter } = createNavigation({
     locales,
     defaultLocale
   });
   ```

2. **Create LanguageSwitcher component**
   ```typescript
   'use client';

   import { useLocale } from 'next-intl';
   import { useRouter, usePathname } from '@/i18n/navigation';
   import { locales, type Locale } from '@/i18n/config';

   const localeNames: Record<Locale, string> = {
     en: 'English',
     vi: 'Tiếng Việt',
     fr: 'Français'
   };

   export function LanguageSwitcher() {
     const locale = useLocale();
     const router = useRouter();
     const pathname = usePathname();

     const handleChange = (newLocale: Locale) => {
       // Set cookie for persistence
       document.cookie = `NEXT_LOCALE=${newLocale}; path=/; max-age=31536000`;
       // Navigate to same page with new locale
       router.replace(pathname, { locale: newLocale });
     };

     return (
       <div className="relative">
         {/* Dropdown implementation */}
       </div>
     );
   }
   ```

3. **Design the dropdown UI** - Scandinavian minimal style
   - Current locale displayed as button
   - Dropdown with all locale options
   - Hover/focus states matching app design

4. **Integrate into Topbar**
   ```typescript
   // In Topbar.tsx, add before user menu
   <LanguageSwitcher />
   ```

5. **Add ARIA attributes** for accessibility
   - `aria-label="Select language"`
   - `aria-expanded` for dropdown state
   - `role="listbox"` for options

## Todo List

- [ ] Create src/i18n/navigation.ts
- [ ] Create src/components/language-switcher.tsx
- [ ] Style dropdown matching Scandinavian design
- [ ] Add keyboard navigation support
- [ ] Add ARIA accessibility attributes
- [ ] Integrate into Topbar.tsx
- [ ] Test cookie persistence
- [ ] Test locale switching on all pages

## Success Criteria

- [ ] Clicking locale changes URL to new locale
- [ ] Current page preserved after switch
- [ ] Cookie `NEXT_LOCALE` set correctly
- [ ] Refreshing page maintains chosen locale
- [ ] Dropdown accessible via keyboard
- [ ] UI matches existing design system

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cookie not persisting | Medium | Check cookie settings, sameSite |
| Navigation losing state | Low | Use router.replace, not push |
| Dropdown z-index issues | Low | Test with all modals/dropdowns |

## Security Considerations

- Locale values validated against allowed list
- Cookie is not httpOnly (needed for client read)
- Cookie path set to `/` for app-wide access

## Next Steps

After completing this phase, proceed to [Phase 05](./phase-05-testing-and-validation.md) for final testing and validation.
