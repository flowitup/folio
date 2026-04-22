---
title: "Multi-Language Internationalization (i18n)"
description: "Implement language switching for Vietnamese, French, and English using next-intl"
status: pending
priority: P2
effort: 3h
branch: main
tags: [i18n, next-intl, localization, ux]
created: 2026-01-26
---

# Multi-Language Internationalization Plan

## Overview

Implement internationalization (i18n) for Construction Management app supporting **English (en)**, **Vietnamese (vi)**, and **French (fr)** using `next-intl` with URL-based locale prefixes and cookie persistence.

## Tech Context

- **Framework**: Next.js 16.1.3 (App Router)
- **React**: 19.2.3
- **Library**: next-intl
- **URL Strategy**: `/en/*`, `/vi/*`, `/fr/*`
- **Default Locale**: English (en)
- **Persistence**: Cookie-based

## Current Architecture

```
src/
├── app/
│   ├── layout.tsx              # Root layout (lang="en" hardcoded)
│   ├── page.tsx                # Landing page
│   ├── login/page.tsx          # Login page
│   ├── unauthorized/page.tsx
│   └── (app)/                  # Protected routes
│       ├── layout.tsx          # App layout with Sidebar/Topbar
│       ├── dashboard/page.tsx
│       ├── projects/page.tsx
│       └── settings/page.tsx
├── components/
│   ├── layout/
│   │   ├── Topbar.tsx          # Header with page titles
│   │   └── Sidebar.tsx         # Navigation sidebar
│   └── auth/
│       └── LoginForm.tsx       # Login form component
├── middleware.ts               # Auth middleware (needs i18n integration)
└── lib/auth/                   # Auth utilities
```

## Target Architecture

```
src/
├── i18n/
│   ├── config.ts               # i18n configuration
│   ├── request.ts              # Server-side i18n request config
│   └── navigation.ts           # Localized navigation helpers
├── messages/
│   ├── en.json                 # English translations
│   ├── vi.json                 # Vietnamese translations
│   └── fr.json                 # French translations
├── app/
│   └── [locale]/               # Dynamic locale segment
│       ├── layout.tsx          # Locale-aware layout
│       ├── page.tsx
│       ├── login/page.tsx
│       └── (app)/...
├── components/
│   └── language-switcher.tsx   # Language selector component
└── middleware.ts               # Combined auth + i18n middleware
```

## Implementation Phases

| Phase | Title | Status | Effort |
|-------|-------|--------|--------|
| 01 | [Core i18n Setup](./phase-01-core-i18n-setup.md) | pending | 45m |
| 02 | [App Router Restructure](./phase-02-app-router-restructure-with-locale-segment.md) | pending | 45m |
| 03 | [Extract Translations](./phase-03-extract-translations-from-components.md) | pending | 30m |
| 04 | [Language Switcher](./phase-04-language-switcher-component.md) | pending | 30m |
| 05 | [Testing & Validation](./phase-05-testing-and-validation.md) | pending | 30m |

## Key Files to Modify

- `next.config.ts` - Add next-intl plugin
- `src/middleware.ts` - Integrate i18n with auth middleware
- `src/app/layout.tsx` - Move to `[locale]/layout.tsx`
- `src/components/layout/Topbar.tsx` - Add language switcher
- `src/components/layout/Sidebar.tsx` - Localize navigation

## Dependencies

- `next-intl` - Core i18n library for Next.js App Router

## Success Criteria

- [ ] All pages accessible via `/en/*`, `/vi/*`, `/fr/*`
- [ ] Language switcher in Topbar works correctly
- [ ] User preference persisted in cookie
- [ ] SSR works with correct locale
- [ ] All visible text translated in 3 languages
- [ ] Existing auth flow unaffected
