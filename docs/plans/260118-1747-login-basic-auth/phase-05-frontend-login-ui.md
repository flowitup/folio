# Phase 05: Frontend Login UI

## Context Links
- [Parent Plan](plan.md)
- [Phase 04: Frontend Auth Infrastructure](phase-04-frontend-auth-infra.md)
- [Next.js Auth Research](research/researcher-02-nextjs-auth-report.md)

## Overview
| Field | Value |
|-------|-------|
| Priority | P1 - Critical |
| Status | complete |
| Review Status | passed (9/10) |
| Completed | 2026-01-18 |
| Estimated Effort | 2h |

Create login page UI, protected route wrapper, and integrate logout functionality into existing layout components.

## Key Insights
- Login form as Client Component (needs interactivity)
- Protected routes use Server Component auth check
- Topbar logout button uses auth context
- Form validation with native HTML5 + custom errors
- Loading states for better UX

## Requirements

### Functional
- Login page with email/password form
- Error display for invalid credentials
- Loading state during authentication
- Redirect to callbackUrl or dashboard after login
- Logout button in Topbar
- Protected route wrapper component

### Non-Functional
- Responsive design (mobile-friendly)
- Accessible form (labels, aria attributes)
- Tailwind CSS styling consistent with existing UI
- No external form libraries (keep simple)

## Architecture

### Component Structure
```
src/
├── app/
│   ├── login/
│   │   └── page.tsx          # Login page (Server Component wrapper)
│   └── (app)/
│       └── layout.tsx        # Protected layout (add auth check)
└── components/
    ├── auth/
    │   ├── LoginForm.tsx     # Client Component
    │   └── ProtectedRoute.tsx # Server Component wrapper
    └── layout/
        └── Topbar.tsx        # Update with logout
```

## Related Code Files

### Files to Create
- `src/app/login/page.tsx`
- `src/components/auth/LoginForm.tsx`
- `src/components/auth/ProtectedRoute.tsx`

### Files to Modify
- `src/components/layout/Topbar.tsx` (add logout button)
- `src/app/(app)/layout.tsx` (add auth check)

## Implementation Steps

### Step 1: Create Login Page

**`src/app/login/page.tsx`**
```typescript
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth/session";
import { LoginForm } from "@/components/auth/LoginForm";

interface LoginPageProps {
  searchParams: Promise<{ callbackUrl?: string }>;
}

export default async function LoginPage({ searchParams }: LoginPageProps) {
  // Redirect if already authenticated
  const session = await getSession();
  if (session) {
    redirect("/dashboard");
  }

  const params = await searchParams;
  const callbackUrl = params.callbackUrl || "/dashboard";

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-12 sm:px-6 lg:px-8">
      <div className="w-full max-w-md space-y-8">
        {/* Logo/Header */}
        <div className="text-center">
          <h1 className="text-3xl font-bold tracking-tight text-gray-900">
            Construction Management
          </h1>
          <h2 className="mt-2 text-lg text-gray-600">
            Sign in to your account
          </h2>
        </div>

        {/* Login Form */}
        <LoginForm callbackUrl={callbackUrl} />

        {/* Footer */}
        <p className="mt-4 text-center text-sm text-gray-500">
          Contact your administrator if you need access.
        </p>
      </div>
    </div>
  );
}
```

### Step 2: Create Login Form Component

**`src/components/auth/LoginForm.tsx`**
```typescript
"use client";

import { useState, FormEvent } from "react";
import { useAuth } from "@/context/AuthContext";

interface LoginFormProps {
  callbackUrl?: string;
}

export function LoginForm({ callbackUrl = "/dashboard" }: LoginFormProps) {
  const { login, isLoading } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!email || !password) {
      setError("Please enter both email and password");
      return;
    }

    const result = await login({ email, password });

    if (!result.success) {
      setError(result.error || "Invalid credentials");
    }
    // Redirect handled by login action
  };

  return (
    <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
      {/* Error Alert */}
      {error && (
        <div
          className="rounded-md bg-red-50 p-4"
          role="alert"
          aria-live="polite"
        >
          <div className="flex">
            <div className="flex-shrink-0">
              <svg
                className="h-5 w-5 text-red-400"
                viewBox="0 0 20 20"
                fill="currentColor"
                aria-hidden="true"
              >
                <path
                  fillRule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                  clipRule="evenodd"
                />
              </svg>
            </div>
            <div className="ml-3">
              <p className="text-sm font-medium text-red-800">{error}</p>
            </div>
          </div>
        </div>
      )}

      {/* Email Field */}
      <div>
        <label
          htmlFor="email"
          className="block text-sm font-medium text-gray-700"
        >
          Email address
        </label>
        <div className="mt-1">
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={isLoading}
            className="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder-gray-400 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-blue-500 disabled:cursor-not-allowed disabled:bg-gray-100 sm:text-sm"
            placeholder="you@example.com"
          />
        </div>
      </div>

      {/* Password Field */}
      <div>
        <label
          htmlFor="password"
          className="block text-sm font-medium text-gray-700"
        >
          Password
        </label>
        <div className="mt-1">
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            minLength={8}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            disabled={isLoading}
            className="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder-gray-400 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-blue-500 disabled:cursor-not-allowed disabled:bg-gray-100 sm:text-sm"
            placeholder="••••••••"
          />
        </div>
      </div>

      {/* Submit Button */}
      <div>
        <button
          type="submit"
          disabled={isLoading}
          className="group relative flex w-full justify-center rounded-md border border-transparent bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isLoading ? (
            <>
              <svg
                className="mr-2 h-5 w-5 animate-spin text-white"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                ></circle>
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                ></path>
              </svg>
              Signing in...
            </>
          ) : (
            "Sign in"
          )}
        </button>
      </div>
    </form>
  );
}
```

### Step 3: Create Protected Route Component

**`src/components/auth/ProtectedRoute.tsx`**
```typescript
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth/session";
import type { ReactNode } from "react";

interface ProtectedRouteProps {
  children: ReactNode;
  requiredPermissions?: string[];
  requiredRoles?: string[];
  fallbackUrl?: string;
}

/**
 * Server Component wrapper for protected routes.
 * Verifies authentication and optionally permissions/roles.
 */
export async function ProtectedRoute({
  children,
  requiredPermissions = [],
  requiredRoles = [],
  fallbackUrl = "/login",
}: ProtectedRouteProps) {
  const session = await getSession();

  // Not authenticated
  if (!session) {
    redirect(fallbackUrl);
  }

  // Check required permissions
  if (requiredPermissions.length > 0) {
    const hasAllPermissions = requiredPermissions.every((perm) =>
      session.user.permissions.includes(perm)
    );
    if (!hasAllPermissions) {
      redirect("/unauthorized");
    }
  }

  // Check required roles
  if (requiredRoles.length > 0) {
    const hasAnyRole = requiredRoles.some((role) =>
      session.user.roles.includes(role)
    );
    if (!hasAnyRole) {
      redirect("/unauthorized");
    }
  }

  return <>{children}</>;
}
```

### Step 4: Update Topbar with Logout

**Update `src/components/layout/Topbar.tsx`**
```typescript
"use client";

import { useAuth } from "@/context/AuthContext";

export function Topbar() {
  const { user, logout, isLoading } = useAuth();

  return (
    <header className="flex h-16 items-center justify-between border-b bg-white px-6">
      {/* Left side - Title/Breadcrumb */}
      <div>
        <h1 className="text-lg font-semibold text-gray-900">Dashboard</h1>
      </div>

      {/* Right side - User menu */}
      <div className="flex items-center gap-4">
        {user && (
          <>
            {/* User info */}
            <span className="text-sm text-gray-600">{user.email}</span>

            {/* Logout button */}
            <button
              onClick={() => logout()}
              disabled={isLoading}
              className="rounded-md bg-gray-100 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {isLoading ? "..." : "Sign out"}
            </button>
          </>
        )}
      </div>
    </header>
  );
}
```

### Step 5: Update App Layout with Auth Check

**Update `src/app/(app)/layout.tsx`**
```typescript
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth/session";
import { Sidebar } from "@/components/layout/Sidebar";
import { Topbar } from "@/components/layout/Topbar";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  // Server-side auth check (primary protection)
  const session = await getSession();

  if (!session) {
    redirect("/login");
  }

  return (
    <div className="flex h-screen bg-gray-50">
      {/* Sidebar */}
      <Sidebar />

      {/* Main content area */}
      <div className="flex flex-1 flex-col overflow-hidden">
        {/* Topbar */}
        <Topbar />

        {/* Page content */}
        <main className="flex-1 overflow-y-auto p-6">{children}</main>
      </div>
    </div>
  );
}
```

### Step 6: Create Unauthorized Page (Optional)

**`src/app/unauthorized/page.tsx`**
```typescript
import Link from "next/link";

export default function UnauthorizedPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-900">403</h1>
        <p className="mt-2 text-lg text-gray-600">
          You don't have permission to access this page.
        </p>
        <Link
          href="/dashboard"
          className="mt-4 inline-block rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
        >
          Go to Dashboard
        </Link>
      </div>
    </div>
  );
}
```

## Todo List

- [x] Create login page
- [x] Create LoginForm client component
- [x] Create ProtectedRoute server component
- [x] Update Topbar with logout button
- [x] Update app layout with auth check
- [x] Create unauthorized page
- [x] Add loading/error states
- [x] Test login flow end-to-end
- [x] Test logout flow
- [x] Test redirect to callbackUrl

## Success Criteria

- [x] Login page displays form correctly
- [x] Form validates email/password
- [x] Error message shows for invalid credentials
- [x] Loading spinner shows during submission
- [x] Successful login redirects to dashboard
- [x] Topbar shows user email and logout button
- [x] Logout clears session and redirects to login
- [x] Protected routes redirect unauthenticated users

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Form flicker on SSR | Medium | Low | Use initialUser prop |
| Double redirect | Low | Medium | Check auth in both middleware and layout |
| Styling inconsistency | Low | Low | Follow existing Tailwind patterns |

## Security Considerations

- Password field uses type="password"
- No password in error messages
- Form disabled during submission (prevent double-submit)
- Auth check in layout (not just middleware)

## Next Steps

After this phase:
→ [Phase 06: Testing & Security](phase-06-testing-security.md)
