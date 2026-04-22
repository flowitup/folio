# Frontend Implementation State

**Last Updated:** 2026-01-27
**Project:** construction-front-end
**Tech Stack:** TypeScript 5, Next.js 16.1.3 (App Router), React 19, Tailwind CSS v4, Shadcn UI
**Architecture:** Server Components + Client Context Hybrid
**Overall Completion:** ~55%

---

## Quick Status

| Category | Status | Completion |
|----------|--------|------------|
| Authentication Framework | COMPLETE | 100% |
| Navigation/Layout | COMPLETE | 100% |
| Login Page | COMPLETE | 100% |
| Dashboard Page | PLACEHOLDER | 10% |
| Projects Page | FUNCTIONAL | 60% |
| Settings Page | PLACEHOLDER | 5% |
| Testing Infrastructure | COMPLETE | 100% |
| API Integration | COMPLETE | 100% |
| UI Component Library | COMPLETE | 100% |
| Internationalization | COMPLETE | 100% |
| Dark Mode | COMPLETE | 100% |

---

## 1. Pages & Routes

### Implemented (Production-Ready)

| Route | Path | Component Type | Purpose |
|-------|------|---------------|---------|
| Login | `/[locale]/login` | Server + Client | User authentication form |
| Unauthorized | `/[locale]/unauthorized` | Server | 403 permission denied |
| Dashboard | `/[locale]/dashboard` | Client | Metrics cards (placeholder data) |
| Projects | `/[locale]/projects` | Client | Project list + selector |
| Settings | `/[locale]/settings` | Client | Settings cards (placeholder) |

### Route Protection

| Layer | File | Mechanism |
|-------|------|-----------|
| Middleware | `src/middleware.ts` | Cookie + locale + i18n routing |
| Layout | `src/app/[locale]/(app)/layout.tsx` | Server-side session check |
| Component | `ProtectedRoute.tsx` | Fine-grained permissions |
| Error | `AuthErrorBoundary.tsx` | Auth error recovery |

---

## 2. Components

### UI Component Library (Shadcn UI) - COMPLETE

| Component | File | Purpose |
|-----------|------|---------|
| Button | `src/components/ui/button.tsx` | Primary/secondary/ghost/outline buttons |
| Input | `src/components/ui/input.tsx` | Form inputs |
| Label | `src/components/ui/label.tsx` | Form labels |
| Select | `src/components/ui/select.tsx` | Dropdown selects (Radix) |
| Card | `src/components/ui/card.tsx` | Content cards |
| Badge | `src/components/ui/badge.tsx` | Status badges |
| Alert | `src/components/ui/alert.tsx` | Error/info alerts |
| DropdownMenu | `src/components/ui/dropdown-menu.tsx` | Dropdown menus |
| Separator | `src/components/ui/separator.tsx` | Visual dividers |

### Layout Components - COMPLETE

#### Sidebar (`src/components/layout/Sidebar.tsx`)

| Property | Value |
|----------|-------|
| Type | Client Component |
| Width | 256px (w-64) |
| Navigation Items | Dashboard, Projects, Settings |
| Features | Active route highlighting, Lucide icons, border-b alignment |

#### Topbar (`src/components/layout/Topbar.tsx`)

| Property | Value |
|----------|-------|
| Type | Client Component |
| Features | Project selector, page title, language switcher, notifications, user avatar, logout |
| State | Uses `useAuth()` hook |

#### LanguageSwitcher (`src/components/language-switcher.tsx`)

| Property | Value |
|----------|-------|
| Type | Client Component |
| Features | DropdownMenu, 3 locales (en/fr/vi), next-intl routing |

#### ThemeToggle (`src/components/theme-toggle.tsx`)

| Property | Value |
|----------|-------|
| Type | Client Component |
| Features | DropdownMenu, 3 modes (light/dark/system), localStorage persistence |

#### ProjectSelector (`src/components/project/ProjectSelector.tsx`)

| Property | Value |
|----------|-------|
| Type | Client Component |
| Features | Radix Select, project context, localStorage persistence |

### Auth Components - COMPLETE

#### LoginForm (`src/components/auth/LoginForm.tsx`)

| Property | Value |
|----------|-------|
| Type | Client Component |
| Props | `callbackUrl?: string` |
| Validation | HTML5 + custom (empty check) |
| Features | Error display, loading spinner, disabled state |

#### ProtectedRoute (`src/components/auth/ProtectedRoute.tsx`)

| Property | Value |
|----------|-------|
| Type | Server Component |
| Props | `children`, `requiredPermissions?`, `requiredRoles?`, `fallbackUrl?` |
| Features | Permission/role checking, redirect on failure |

#### AuthErrorBoundary (`src/context/AuthErrorBoundary.tsx`)

| Property | Value |
|----------|-------|
| Type | Class Component (Error Boundary) |
| Features | Error fallback UI, recovery button, console logging |

---

## 3. State Management

### AuthContext - COMPLETE

**Location:** `src/context/AuthContext.tsx`

| Export | Type | Purpose |
|--------|------|---------|
| `AuthProvider` | Component | Wraps entire app |
| `useAuth()` | Hook | Access auth state |

**Context State:**

```typescript
interface AuthContextValue {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (credentials: LoginCredentials) => Promise<LoginResult>;
  logout: () => void;
}
```

### ThemeContext - COMPLETE

**Location:** `src/context/ThemeContext.tsx`

| Export | Type | Purpose |
|--------|------|---------| | `ThemeProvider` | Component | Wraps entire app |
| `useTheme()` | Hook | Access theme state (light/dark/system) |

**Context State:**

```typescript
interface ThemeContextValue {
  theme: 'light' | 'dark' | 'system';
  setTheme: (theme: 'light' | 'dark' | 'system') => void;
}
```

### Session Management - COMPLETE

**Location:** `src/lib/auth/session.ts`

| Function | Purpose |
|----------|---------|
| `getSession()` | Fetch session from cookies + backend |
| `getCurrentUser()` | Get user from session |
| `hasPermission(perm)` | Check single permission |
| `hasRole(role)` | Check role assignment |

---

## 4. API Integration

### HTTP Client - COMPLETE

**Location:** `src/lib/api/http.ts`

| Method | Signature |
|--------|-----------|
| `api.get<T>` | `(endpoint, options?) => Promise<T>` |
| `api.post<T, B>` | `(endpoint, body, options?) => Promise<T>` |
| `api.put<T, B>` | `(endpoint, body, options?) => Promise<T>` |
| `api.patch<T, B>` | `(endpoint, body, options?) => Promise<T>` |
| `api.delete<T>` | `(endpoint, options?) => Promise<T>` |

**Features:**
- Typed generics
- Automatic cookie handling (`credentials: "include"`)
- Custom `ApiError` class

### Backend Endpoints Called

| Endpoint | Location | Purpose |
|----------|----------|---------|
| POST `/auth/login` | actions.ts | Login |
| POST `/auth/logout` | actions.ts | Logout |
| POST `/auth/refresh` | actions.ts | Token refresh |
| GET `/auth/me` | session.ts | Current user |

---

## 5. Server Actions - COMPLETE

**Location:** `src/lib/auth/actions.ts`

| Action | Purpose | Returns |
|--------|---------|---------|
| `login(credentials)` | Authenticate user | `{ success, user?, error? }` |
| `logout()` | Clear session | Redirect to `/login` |
| `refreshToken()` | Refresh access token | `{ success, error? }` |

---

## 6. Authentication Flow

### Login Flow

```
LoginForm (input email/password)
    ↓
loginAction (Server Action)
    ↓
POST /api/v1/auth/login (Backend)
    ↓
Forward Set-Cookie headers
    ↓
Update AuthContext
    ↓
router.push("/dashboard")
```

### Session Initialization (SSR)

```
RootLayout (Server)
    ↓
getCurrentUser()
    ↓
Pass initialUser to AuthProvider
    ↓
Client hydrates with server data
```

### Logout Flow

```
Click "Sign out"
    ↓
logout() Server Action
    ↓
Delete cookies
    ↓
POST /auth/logout (best effort)
    ↓
redirect("/login")
```

---

## 7. Styling

### Setup - COMPLETE

| File | Purpose |
|------|---------|
| `globals.css` | Tailwind imports, CSS variables |
| `postcss.config.mjs` | PostCSS configuration |

### Theme Variables

```css
/* Light mode (default) */
--background: #FFFFFF;
--foreground: #0F172A;
--primary: #3B82F6;        /* Blue 500 - fintech accent */
--card: #FFFFFF;
--muted: #F1F5F9;

/* Dark mode (.dark class or system preference) */
--background: #0F172A;
--foreground: #F8FAFC;
--primary: #60A5FA;        /* Blue 400 */
--card: #1E293B;
--muted: #334155;
```

### Dark Mode Implementation

- **ThemeContext** manages state (light/dark/system)
- **localStorage** persists user preference
- **Manual toggle** via dropdown in Topbar
- **CSS** uses `.dark` class for dark mode styles

### Class Composition Utility

```typescript
// src/lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### Component Patterns

| Pattern | Classes |
|---------|---------|
| Button (Primary) | `Button variant="default"` |
| Button (Outline) | `Button variant="outline" size="sm"` |
| Card | `Card` + `CardHeader` + `CardContent` |
| Input | `Input` + `Label` |
| Alert (Error) | `Alert variant="destructive"` |

---

## 8. Testing Infrastructure - COMPLETE

### Configuration

| File | Purpose |
|------|---------|
| `vitest.config.ts` | Test runner config |
| `src/test-setup.ts` | Global test setup |
| `src/vitest-setup.ts` | Testing Library setup |

### Test Files

| File | Tests | Coverage |
|------|-------|----------|
| `api-error.test.ts` | 5 | ApiError class |
| `env-config.test.ts` | 6 | Environment config |
| `formatters.test.ts` | 21 | Utility formatters |
| `setup.test.ts` | 2 | Test setup validation |
| `ProjectContext.test.tsx` | 9 | Project state management |
| `ProjectSelector.test.tsx` | 12 | Radix Select component |
| `projects.test.ts` | 8 | Projects API |

**Total:** 63 unit tests (all passing)

### Scripts

| Command | Purpose |
|---------|---------|
| `npm run test` | Run all tests |
| `npm run test:watch` | Watch mode |
| `npm run type-check` | TypeScript check |
| `npm run lint` | ESLint |
| `npm run build` | Production build |

---

## 9. Internationalization (i18n) - COMPLETE

### Configuration

| File | Purpose |
|------|---------|
| `src/i18n/config.ts` | Locale definitions (en, fr, vi) |
| `src/i18n/routing.ts` | Centralized locale routing config |
| `src/i18n/navigation.ts` | Localized Link/useRouter (uses routing.ts) |
| `src/i18n/request.ts` | next-intl request config |
| `src/messages/*.json` | Translation files (Dashboard → Overview, Projects fully translated) |

### Usage

```typescript
// In components
import { useTranslations } from "next-intl";
const t = useTranslations("navigation");
t("dashboard"); // "Dashboard" or "Tableau de bord"

// Routing
import { Link } from "@/i18n/navigation";
<Link href="/dashboard">...</Link> // Auto-prefixes locale
```

---

## 10. Server vs Client Components

### Server Components

| File | Purpose |
|------|---------|
| `src/app/[locale]/layout.tsx` | Root layout (auth init, i18n) |
| `src/app/[locale]/(app)/layout.tsx` | App layout (session check) |
| `src/app/[locale]/login/page.tsx` | Login page |
| `ProtectedRoute.tsx` | Permission wrapper |

### Client Components

| File | Purpose |
|------|---------|
| `AuthContext.tsx` | Auth state provider |
| `ThemeContext.tsx` | Theme state provider |
| `AuthErrorBoundary.tsx` | Error boundary |
| `ProjectContext.tsx` | Project state provider |
| `LoginForm.tsx` | Login form |
| `Sidebar.tsx` | Navigation |
| `Topbar.tsx` | Header |
| `LanguageSwitcher.tsx` | Locale dropdown |
| `theme-toggle.tsx` | Theme dropdown |
| `ProjectSelector.tsx` | Project select |
| `dashboard/page.tsx` | Dashboard page |
| `projects/page.tsx` | Projects page |
| `settings/page.tsx` | Settings page |

---

## 10. Environment Configuration

### Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `NEXT_PUBLIC_API_BASE_URL` | Yes | Backend API URL |
| `NODE_ENV` | Auto | Environment |

### Config Files

| File | Purpose |
|------|---------|
| `.env.example` | Template |
| `.env.local` | Local config (git-ignored) |
| `tsconfig.json` | TypeScript (strict mode) |
| `next.config.ts` | Next.js config (empty) |

---

## 11. Pending Implementation Tasks

### High Priority

1. **Dashboard Page**
   - [ ] Active projects count widget (API integration)
   - [ ] Pending tasks count widget
   - [ ] Team members count widget
   - [ ] Charts/visualizations

2. **Projects Page**
   - [x] Projects list/grid view
   - [x] Project selector
   - [ ] Create project form
   - [ ] Edit project modal
   - [ ] Delete confirmation
   - [ ] Filtering/sorting
   - [ ] Pagination

3. **Settings Page**
   - [ ] Profile settings form
   - [ ] Password change form
   - [ ] Notification preferences
   - [ ] Organization settings

### Medium Priority

4. **Mobile Responsiveness**
   - [ ] Sidebar collapse on mobile
   - [ ] Hamburger menu
   - [ ] Responsive layouts

5. **Token Auto-Refresh**
   - [ ] Automatic refresh on 401
   - [ ] Background refresh timer

### Low Priority

6. **Dark Mode Toggle**
   - [x] System preference detection
   - [x] Manual theme switcher
   - [x] Persist preference (localStorage)

7. **User Registration**
   - [ ] Signup form
   - [ ] Email verification

8. **Password Reset**
   - [ ] Forgot password form
   - [ ] Reset email flow

9. **Notifications UI**
   - [ ] Notification dropdown
   - [ ] Real-time updates

---

## 12. File Structure Reference

```
construction-front-end/
├── src/
│   ├── app/
│   │   ├── layout.tsx           # Root layout
│   │   ├── page.tsx             # Home (placeholder)
│   │   ├── globals.css          # Tailwind + theme
│   │   ├── login/
│   │   │   └── page.tsx         # Login page
│   │   ├── unauthorized/
│   │   │   └── page.tsx         # 403 page
│   │   └── (app)/
│   │       ├── layout.tsx       # App layout
│   │       ├── dashboard/
│   │       │   └── page.tsx     # Dashboard (placeholder)
│   │       ├── projects/
│   │       │   └── page.tsx     # Projects (placeholder)
│   │       └── settings/
│   │           └── page.tsx     # Settings (placeholder)
│   ├── components/
│   │   ├── auth/
│   │   │   ├── LoginForm.tsx    # Login form
│   │   │   └── ProtectedRoute.tsx
│   │   └── layout/
│   │       ├── Sidebar.tsx      # Navigation
│   │       └── Topbar.tsx       # Header
│   ├── context/
│   │   ├── AuthContext.tsx      # Auth provider
│   │   ├── ThemeContext.tsx     # Theme provider
│   │   └── AuthErrorBoundary.tsx
│   ├── lib/
│   │   ├── api/
│   │   │   └── http.ts          # HTTP client
│   │   ├── auth/
│   │   │   ├── actions.ts       # Server actions
│   │   │   ├── session.ts       # Session utils
│   │   │   └── types.ts         # Auth types
│   │   ├── config/
│   │   │   └── env.ts           # Environment config
│   │   └── utils/
│   │       └── formatters.ts    # Utility functions
│   ├── middleware.ts            # Route protection
│   └── __tests__/               # Unit tests
├── public/                      # Static assets
├── package.json
├── tsconfig.json
└── vitest.config.ts
```

---

## 13. Dependencies

### Production

| Package | Version | Purpose |
|---------|---------|---------|
| next | 16.1.3 | Framework |
| react | 19.2.3 | UI library |
| react-dom | 19.2.3 | DOM rendering |
| tailwindcss | 4.x | Styling |
| next-intl | 4.7.0 | Internationalization |
| @radix-ui/* | 2.x | UI primitives (Select, DropdownMenu, etc) |
| class-variance-authority | 0.7.1 | Component variants |
| clsx | 2.1.1 | Class composition |
| tailwind-merge | 3.4.0 | Tailwind class merging |
| lucide-react | 0.563.0 | Icons |

### Development

| Package | Version | Purpose |
|---------|---------|---------|
| typescript | 5.x | Type checking |
| vitest | 4.0.17 | Testing |
| @testing-library/react | 16.3.1 | Component testing |
| @testing-library/dom | 10.4.1 | DOM testing |
| jsdom | 27.4.0 | DOM environment |
| eslint | 9.x | Linting |

---

## 14. Component Props Reference

### LoginForm

```typescript
interface LoginFormProps {
  callbackUrl?: string;
}
```

### ProtectedRoute

```typescript
interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredPermissions?: string[];
  requiredRoles?: string[];
  fallbackUrl?: string;
}
```

### AuthContext

```typescript
interface User {
  id: string;
  email: string;
  permissions: string[];
  roles: string[];
}

interface LoginCredentials {
  email: string;
  password: string;
}

interface LoginResult {
  success: boolean;
  error?: string;
}
```

---

*Document generated from codebase analysis on 2026-01-19*
