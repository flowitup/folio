# Frontend Code Standards

**Last Updated:** 2026-01-18
**Version:** 1.0

## Overview

Frontend code standards for Next.js 16 + React 19 project using TypeScript, Vitest, and React Testing Library.

## File Structure

```
src/
├── __tests__/           # Test files (Vitest)
│   ├── setup.test.ts    # Setup verification tests
│   ├── components/      # Component tests
│   ├── pages/           # Page tests
│   └── utils/           # Utility function tests
├── app/                 # Next.js App Router
│   ├── (auth)/          # Route groups
│   ├── (protected)/     # Protected routes
│   ├── layout.tsx       # Root layout
│   └── page.tsx         # Home page
├── components/          # React components
│   ├── ui/              # UI components
│   ├── forms/           # Form components
│   └── layout/          # Layout components
├── lib/                 # Utility functions
│   ├── auth/            # Authentication utilities
│   └── api/             # API client
└── types/               # TypeScript types
```

## Naming Conventions

### Files & Folders

**Format:** `kebab-case`

**Examples:**
- `user-profile.tsx`
- `auth-context.tsx`
- `api-client.ts`

### Components

**Format:** `PascalCase`

**Examples:**
- `UserProfile`
- `AuthContext`
- `LoginForm`

### Functions & Variables

**Format:** `camelCase`

**Examples:**
- `getUserProfile()`
- `handleLogin()`
- `isLoading`

### Constants

**Format:** `UPPER_SNAKE_CASE`

**Examples:**
- `API_BASE_URL`
- `TOKEN_EXPIRY_MINUTES`
- `MAX_RETRY_ATTEMPTS`

### Types & Interfaces

**Format:** `PascalCase`

**Examples:**
- `UserProfile`
- `AuthSession`
- `ApiResponse<T>`

**Interfaces:** Use for object shapes with behavior
**Type aliases:** Use for union types, primitives, utility types

## Testing Standards

### Test Organization

**Structure:**
```
src/__tests__/
├── setup.test.ts        # Setup verification tests
├── components/          # Component tests
│   └── UserProfile.test.tsx
├── pages/               # Page tests
│   └── Login.test.tsx
└── utils/               # Utility function tests
    └── api-client.test.ts
```

### Test Runner Configuration

**File:** `vitest.config.ts`

```typescript
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
```

### Test Scripts

```bash
npm run test          # Run all tests once
npm run test:watch    # Run tests in watch mode (development)
npm run type-check    # TypeScript compiler check
```

### Test Naming

**Format:** `test_{component/feature}_{scenario}_{expected_result}`

**Examples:**
- `test_setup_verify_vitest_configuration()`
- `test_login_page_valid_credentials_redirects_to_dashboard()`
- `test_logout_clears_cookies_and_session()`
- `test_api_client_handle_network_error_retries()`

### Test Structure (AAA Pattern)

**Arrange-Act-Assert:**

```typescript
import { describe, it, expect } from 'vitest'

describe('Test Framework Setup', () => {
  it('should verify Vitest is configured correctly', () => {
    // Arrange
    const expected = true

    // Act
    const actual = true

    // Assert
    expect(actual).toBe(expected)
  })
})
```

### Component Testing

**Framework:** React Testing Library
**Philosophy:** Test user behavior, not implementation details

**Example:**
```typescript
import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import LoginForm from '@/components/forms/LoginForm'

describe('LoginForm', () => {
  it('should render email and password inputs', () => {
    // Arrange & Act
    render(<LoginForm />)

    // Assert
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument()
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument()
  })

  it('should show validation error for invalid email', async () => {
    // Arrange
    render(<LoginForm />)

    // Act
    const emailInput = screen.getByLabelText(/email/i)
    await userEvent.type(emailInput, 'invalid-email')

    // Assert
    expect(screen.getByText(/invalid email/i)).toBeInTheDocument()
  })
})
```

### Path Aliases

**Configuration:** `@/*` → `./src/*`

**Usage in tests:**
```typescript
import { myFunction } from '@/utils/myFile'
import { MyComponent } from '@/components/MyComponent'
```

### Test Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| vitest | ^4.0.17 | Fast test runner with native ESM support |
| @vitejs/plugin-react | ^5.1.2 | JSX transformation for React 19 |
| jsdom | ^27.4.0 | DOM simulation environment |
| @testing-library/react | ^16.3.1 | React component testing utilities (React 19 compatible) |
| @testing-library/dom | ^10.4.1 | DOM testing utilities |
| @testing-library/user-event | ^14.5.2 | Simulate user interactions |

### Test Coverage

**Target:** >80%

**Run coverage:**
```bash
npm run test -- --coverage
```

### Best Practices

**DO:**
- Test user behavior and interactions
- Use semantic queries (`getByRole`, `getByLabelText`)
- Test error states and edge cases
- Mock external dependencies (API calls, cookies)
- Write descriptive test names

**DON'T:**
- Test implementation details (component state, methods)
- Query by CSS classes or test IDs (unless necessary)
- Over-mock (test realistic scenarios)
- Test third-party library behavior

## React Component Standards

### Functional Components

**Rule:** Use functional components with hooks (no class components)

**Example:**
```typescript
interface UserProfileProps {
  user: User
  onUpdate: (user: User) => void
}

export function UserProfile({ user, onUpdate }: UserProfileProps) {
  const [isEditing, setIsEditing] = useState(false)

  // Component logic
}
```

### Props Interface

**Format:** Prefix component props with component name

**Example:**
```typescript
interface UserProfileProps {
  user: User
  onUpdate?: (user: User) => void
  className?: string
}
```

### State Management

**Prefer:**
- `useState` for local component state
- `useReducer` for complex state logic
- Context API for global state (auth, theme)

**Avoid:**
- Redux for simple apps (use Zustand/Jotai if needed)
- Excessive prop drilling (use context)

### Server Components vs. Client Components

**Server Components (default):**
- No interactivity
- No `useEffect`, `useState`, etc.
- Direct database access

**Client Components:**
- Add `'use client'` directive
- Use hooks, event handlers, browser APIs

**Example:**
```typescript
'use client'

import { useState } from 'react'

export function InteractiveButton() {
  const [count, setCount] = useState(0)
  // ...
}
```

### Error Boundaries

**Use for:**
- Component-level error handling
- Graceful fallback UI

**Example:**
```typescript
'use client'

import { Component, ReactNode } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

export class ErrorBoundary extends Component<Props, { hasError: boolean }> {
  state = { hasError: false }

  static getDerivedStateFromError() {
    return { hasError: true }
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || <div>Something went wrong</div>
    }
    return this.props.children
  }
}
```

## TypeScript Standards

### Strict Mode

**Enabled:** `strict: true` in `tsconfig.json`

### Type Definitions

**Use:**
- Interfaces for object shapes
- Type aliases for unions, primitives, utility types

**Example:**
```typescript
// Interface (object shape)
interface User {
  id: string
  email: string
  permissions: string[]
}

// Type alias (union)
type UserRole = 'admin' | 'manager' | 'user'

// Type alias (utility)
type ApiResponse<T> = {
  data: T
  error: string | null
}
```

### Avoid `any`

**Use instead:**
- `unknown` for truly unknown types
- Generics for reusable types
- Type guards for runtime checks

**Example:**
```typescript
// Bad
function process(data: any) {
  return data.value
}

// Good
function process<T extends { value: unknown }>(data: T) {
  return data.value
}
```

### Type Imports

**Use:** `import type { TypeName }` for type-only imports

**Example:**
```typescript
import type { User } from '@/types/user'
```

## API Client Standards

### HTTP Client

**Library:** Native `fetch` (or axios if needed)
**Location:** `src/lib/api/http.ts`

### Error Handling

**Standardized error response:**
```typescript
interface ApiError {
  error: string
  message: string
  status_code: number
}
```

### Request/Response Types

**Example:**
```typescript
// Request
interface LoginRequest {
  email: string
  password: string
}

// Response
interface LoginResponse {
  access_token: string
  refresh_token: string
  user: User
}
```

## Code Quality Tools

### Linting

**Tool:** ESLint v9 (flat config)
**Config:** `eslint.config.mjs`

**Command:**
```bash
npm run lint
```

### Type Checking

**Command:**
```bash
npm run type-check
```

### Formatting

**Tool:** Prettier
**Config:** `.prettierrc`

**Command:**
```bash
npm run format
```

## Performance Guidelines

### Code Splitting

**Use:** Next.js automatic code splitting
**Route-based:** Automatic for `app/` directory
**Dynamic imports:** For heavy components

**Example:**
```typescript
import dynamic from 'next/dynamic'

const HeavyChart = dynamic(() => import('@/components/HeavyChart'), {
  loading: () => <div>Loading...</div>,
})
```

### Image Optimization

**Use:** `next/image` component

**Example:**
```typescript
import Image from 'next/image'

<Image
  src="/profile.jpg"
  alt="Profile"
  width={200}
  height={200}
  priority
/>
```

### Font Optimization

**Use:** `next/font/google` or `next/font/local`

**Example:**
```typescript
import { Inter } from 'next/font/google'

const inter = Inter({ subsets: ['latin'] })
```

## UI Component Library

**Framework:** Shadcn UI (Radix UI primitives + Tailwind CSS)
**Location:** `src/components/ui/`

### Component Architecture

**Copy-paste approach:** Components are copied into the project, fully editable
**Primitive library:** Radix UI for accessible component foundation
**Styling:** Tailwind CSS with CSS variables
**Icons:** Lucide React

### Installed Components

| Component | File | Purpose |
|-----------|------|---------|
| Button | `button.tsx` | Primary/secondary/destructive buttons |
| Input | `input.tsx` | Text input fields |
| Label | `label.tsx` | Form field labels |
| Select | `select.tsx` | Dropdown selects |
| Card | `card.tsx` | Content containers |
| Badge | `badge.tsx` | Status indicators |
| Alert | `alert.tsx` | Error/warning messages |
| DropdownMenu | `dropdown-menu.tsx` | Context menus |
| Separator | `separator.tsx` | Visual dividers |

### cn() Utility Pattern

**Location:** `src/lib/utils.ts`
**Purpose:** Merge Tailwind classes with conflict resolution

```typescript
import { cn } from "@/lib/utils"

// Usage
<Button className={cn("custom-class", conditional && "extra-class")} />
```

**Dependencies:**
- `clsx` - Conditional class composition
- `tailwind-merge` - Intelligent class merging

### Design System Integration

**Theme variables:** Defined in `src/app/globals.css`
**Color palette:** Fintech blue design system
**Base color:** Neutral (Tailwind slate)

**Shadcn CSS Variables:**
```css
--background, --foreground, --primary, --primary-foreground
--secondary, --muted, --accent, --destructive
--border, --input, --ring, --radius
```

**Fintech custom variables:**
```css
--accent-primary, --bg-elevated, --text-primary
--border-default, --status-positive, --shadow-md
```

### Component Usage Examples

**Button:**
```typescript
import { Button } from "@/components/ui/button"

<Button variant="default">Primary</Button>
<Button variant="secondary">Secondary</Button>
<Button variant="destructive">Delete</Button>
```

**Input + Label:**
```typescript
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"

<Label htmlFor="email">Email</Label>
<Input id="email" type="email" />
```

**Card:**
```typescript
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"

<Card>
  <CardHeader>
    <CardTitle>Title</CardTitle>
  </CardHeader>
  <CardContent>Content</CardContent>
</Card>
```

**Select:**
```typescript
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"

<Select>
  <SelectTrigger>
    <SelectValue placeholder="Choose option" />
  </SelectTrigger>
  <SelectContent>
    <SelectItem value="1">Option 1</SelectItem>
  </SelectContent>
</Select>
```

## Internationalization (i18n)

**Framework:** next-intl
**Supported locales:** en (English), vi (Vietnamese)

### Configuration

**Middleware:** `src/middleware.ts` - Locale routing
**i18n config:** `src/i18n/request.ts` - Translation loader
**Messages location:** `messages/{locale}.json`

### Usage Pattern

```typescript
import { useTranslations } from 'next-intl'

export default function Page() {
  const t = useTranslations('namespace')
  return <h1>{t('key')}</h1>
}
```

### Routing

**Format:** `/{locale}/path`
**Examples:** `/en/dashboard`, `/vi/dashboard`
**Default:** English (en)

## Unresolved Questions

- State management strategy for complex app state (Context vs. Zustand)
- Form library choice (React Hook Form vs. native FormData)
- Data fetching strategy (SWR vs. React Query vs. Server Components)
