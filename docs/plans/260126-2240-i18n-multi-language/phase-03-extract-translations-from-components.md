# Phase 03: Extract Translations from Components

## Context

- **Parent Plan**: [plan.md](./plan.md)
- **Dependencies**: [Phase 02](./phase-02-app-router-restructure-with-locale-segment.md)
- **Docs**: [next-intl useTranslations](https://next-intl-docs.vercel.app/docs/usage/messages)

## Overview

- **Priority**: High
- **Status**: pending
- **Effort**: 30m

Extract all hardcoded strings from components and pages into translation JSON files. Organize translations by namespace for maintainability.

## Key Insights

- Use namespaces to organize translations (common, auth, dashboard, etc.)
- Server components use `getTranslations()`
- Client components use `useTranslations()` hook
- Keep translation keys descriptive and hierarchical

## Requirements

### Functional
- All user-visible text externalized to JSON files
- Translations for English, Vietnamese, French
- Namespace-based organization

### Non-Functional
- Type-safe translation keys (optional enhancement)
- Consistent naming convention for keys
- No missing translations

## Architecture

### Translation Namespaces

```
messages/
├── en.json
├── vi.json
└── fr.json

# Structure inside each JSON:
{
  "common": {
    "appName": "Construction",
    "signOut": "Sign out",
    "loading": "Loading..."
  },
  "navigation": {
    "dashboard": "Dashboard",
    "projects": "Projects",
    "settings": "Settings"
  },
  "auth": {
    "welcomeBack": "Welcome back",
    "signInPrompt": "Sign in to your account to continue",
    "emailLabel": "Email address",
    "passwordLabel": "Password",
    "signIn": "Sign in",
    "signingIn": "Signing in..."
  },
  "dashboard": {
    "title": "Dashboard",
    "welcome": "Welcome to the Construction Management Dashboard.",
    "activeProjects": "Active Projects",
    "pendingTasks": "Pending Tasks",
    "teamMembers": "Team Members",
    "awaitingData": "Awaiting data",
    "recentActivity": "Recent Activity",
    "noActivity": "No recent activity to display"
  },
  "settings": {
    "title": "Settings",
    "description": "Configure your application settings here.",
    "profile": "Profile Settings",
    "profileDesc": "Manage your personal information",
    "notifications": "Notification Preferences",
    "notificationsDesc": "Control how you receive notifications",
    "organization": "Organization Settings",
    "organizationDesc": "Manage organization-level settings",
    "comingSoon": "will be available soon"
  }
}
```

## Related Code Files

### Files to Modify
- `src/messages/en.json` - Add all English translations
- `src/messages/vi.json` - Add Vietnamese translations
- `src/messages/fr.json` - Add French translations
- `src/components/layout/Topbar.tsx` - Use useTranslations
- `src/components/layout/Sidebar.tsx` - Use useTranslations
- `src/components/auth/LoginForm.tsx` - Use useTranslations
- `src/app/[locale]/page.tsx` - Use getTranslations
- `src/app/[locale]/login/page.tsx` - Use getTranslations
- `src/app/[locale]/(app)/dashboard/page.tsx` - Use useTranslations
- `src/app/[locale]/(app)/settings/page.tsx` - Use useTranslations

## Implementation Steps

1. **Populate en.json** with all extracted strings
   - Scan all components for hardcoded text
   - Organize by namespace

2. **Translate to vi.json** (Vietnamese)
   ```json
   {
     "common": {
       "appName": "Construction",
       "signOut": "Đăng xuất"
     },
     "navigation": {
       "dashboard": "Bảng điều khiển",
       "projects": "Dự án",
       "settings": "Cài đặt"
     },
     "auth": {
       "welcomeBack": "Chào mừng trở lại",
       "signInPrompt": "Đăng nhập để tiếp tục"
     }
   }
   ```

3. **Translate to fr.json** (French)
   ```json
   {
     "common": {
       "appName": "Construction",
       "signOut": "Déconnexion"
     },
     "navigation": {
       "dashboard": "Tableau de bord",
       "projects": "Projets",
       "settings": "Paramètres"
     },
     "auth": {
       "welcomeBack": "Bienvenue",
       "signInPrompt": "Connectez-vous pour continuer"
     }
   }
   ```

4. **Update Client Components** (Topbar, Sidebar, LoginForm, DashboardPage)
   ```typescript
   'use client';
   import { useTranslations } from 'next-intl';

   export function Component() {
     const t = useTranslations('namespace');
     return <h1>{t('key')}</h1>;
   }
   ```

5. **Update Server Components** (LoginPage, etc.)
   ```typescript
   import { getTranslations } from 'next-intl/server';

   export default async function Page() {
     const t = await getTranslations('namespace');
     return <h1>{t('key')}</h1>;
   }
   ```

## Todo List

- [ ] Create complete en.json with all namespaces
- [ ] Create vi.json with Vietnamese translations
- [ ] Create fr.json with French translations
- [ ] Update Topbar.tsx with useTranslations
- [ ] Update Sidebar.tsx with useTranslations
- [ ] Update LoginForm.tsx with useTranslations
- [ ] Update login/page.tsx with getTranslations
- [ ] Update dashboard/page.tsx with useTranslations
- [ ] Update settings/page.tsx with useTranslations
- [ ] Verify no hardcoded strings remain

## Success Criteria

- [ ] All visible text uses translation functions
- [ ] Switching locale changes all text
- [ ] No missing translation warnings in console
- [ ] All 3 languages display correctly

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing translations | Medium | Cross-check all JSON files |
| Translation key typos | Low | Use TypeScript for key safety |
| Wrong namespace import | Low | Consistent naming convention |

## Security Considerations

- No user input in translation keys
- Translations are static JSON files
- No XSS risk from translation content

## Next Steps

After completing this phase, proceed to [Phase 04](./phase-04-language-switcher-component.md) to implement the language switcher UI.
