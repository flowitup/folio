# Phase 04: Frontend Auth Infrastructure

## Context Links
- [Parent Plan](plan.md)
- [Phase 03: Backend Auth Endpoints](phase-03-backend-auth-endpoints.md)
- [Next.js Auth Research](research/researcher-02-nextjs-auth-report.md)

## Overview
| Field | Value |
|-------|-------|
| Priority | P1 - Critical |
| Status | complete |
| Review Status | reviewed (9/10) |
| Estimated Effort | 2h |
| Completed | 2026-01-18 |

Set up authentication infrastructure for Next.js 15 frontend: auth context/provider, middleware for route protection, API client updates, and server actions.

## Key Insights
- Server-first auth approach (verify in Server Components)
- Middleware for early redirect (not sole protection)
- httpOnly cookies for token storage (auto-sent by browser)
- Client Context for UI state only
- Server Actions for mutations with auth checks

## Requirements

### Functional
- Auth context/provider for client-side state
- Middleware to redirect unauthenticated users
- API client updates with credentials:include
- Server actions for login/logout
- Auth utility functions

### Non-Functional
- TypeScript types for auth data
- Minimal client-side state
- SSR-compatible patterns

## Architecture

### Auth Flow Diagram
```
┌─────────────────────────────────────────────────────┐
│                    NEXT.JS 15                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  MIDDLEWARE (middleware.ts)                         │
│  ┌─────────────────────────────────────────────┐   │
│  │ Check cookie → Redirect /login if missing    │   │
│  └─────────────────────────────────────────────┘   │
│                     ↓                               │
│  SERVER COMPONENT (page.tsx)                        │
│  ┌─────────────────────────────────────────────┐   │
│  │ getSession() → Verify token → Fetch data     │   │
│  └─────────────────────────────────────────────┘   │
│                     ↓                               │
│  CLIENT COMPONENT (AuthProvider)                    │
│  ┌─────────────────────────────────────────────┐   │
│  │ UI state, login/logout handlers              │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Related Code Files

### Files to Create
- `src/lib/auth/types.ts` (auth TypeScript types)
- `src/lib/auth/session.ts` (server-side session utils)
- `src/lib/auth/actions.ts` (server actions)
- `src/lib/auth/middleware.ts` (auth middleware helpers)
- `src/context/AuthContext.tsx` (client context/provider)
- `src/middleware.ts` (Next.js middleware)

### Files to Modify
- `src/lib/api/http.ts` (add credentials:include)
- `src/app/layout.tsx` (wrap with AuthProvider)

## Implementation Steps

### Step 1: Create Auth Types

**`src/lib/auth/types.ts`**
```typescript
export interface User {
  id: string;
  email: string;
  permissions: string[];
  roles: string[];
}

export interface AuthSession {
  user: User;
  accessToken: string;
  expiresAt: number;
}

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number;
  user: User;
}

export interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}
```

### Step 2: Create Server-Side Session Utils

**`src/lib/auth/session.ts`**
```typescript
import { cookies } from "next/headers";
import { env } from "@/lib/config/env";
import type { User, AuthSession } from "./types";

const ACCESS_TOKEN_COOKIE = "access_token_cookie";

/**
 * Get current session from server-side cookies.
 * Use in Server Components and Server Actions.
 */
export async function getSession(): Promise<AuthSession | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(ACCESS_TOKEN_COOKIE)?.value;

  if (!token) {
    return null;
  }

  try {
    // Verify token with backend
    const response = await fetch(`${env.apiBaseUrl}/auth/me`, {
      headers: {
        Cookie: `${ACCESS_TOKEN_COOKIE}=${token}`,
      },
      cache: "no-store",
    });

    if (!response.ok) {
      return null;
    }

    const user: User = await response.json();

    return {
      user,
      accessToken: token,
      expiresAt: Date.now() + 30 * 60 * 1000, // 30 min estimate
    };
  } catch {
    return null;
  }
}

/**
 * Get current user from session.
 * Convenience wrapper for getSession().
 */
export async function getCurrentUser(): Promise<User | null> {
  const session = await getSession();
  return session?.user ?? null;
}

/**
 * Check if user has specific permission.
 */
export async function hasPermission(permission: string): Promise<boolean> {
  const user = await getCurrentUser();
  if (!user) return false;
  return user.permissions.includes(permission);
}

/**
 * Check if user has specific role.
 */
export async function hasRole(role: string): Promise<boolean> {
  const user = await getCurrentUser();
  if (!user) return false;
  return user.roles.includes(role);
}
```

### Step 3: Create Server Actions

**`src/lib/auth/actions.ts`**
```typescript
"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { env } from "@/lib/config/env";
import type { LoginCredentials, LoginResponse, User } from "./types";

/**
 * Login server action.
 * Calls backend API and sets cookies.
 */
export async function login(
  credentials: LoginCredentials
): Promise<{ success: boolean; error?: string; user?: User }> {
  try {
    const response = await fetch(`${env.apiBaseUrl}/auth/login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(credentials),
      credentials: "include",
    });

    if (!response.ok) {
      const error = await response.json();
      return {
        success: false,
        error: error.message || "Invalid credentials",
      };
    }

    const data: LoginResponse = await response.json();

    // Forward cookies from backend response
    const setCookieHeaders = response.headers.getSetCookie();
    const cookieStore = await cookies();

    for (const cookie of setCookieHeaders) {
      const [nameValue] = cookie.split(";");
      const [name, value] = nameValue.split("=");
      cookieStore.set(name, value, {
        httpOnly: true,
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax",
        path: "/",
      });
    }

    return {
      success: true,
      user: data.user,
    };
  } catch (error) {
    console.error("Login error:", error);
    return {
      success: false,
      error: "An unexpected error occurred",
    };
  }
}

/**
 * Logout server action.
 * Clears cookies and calls backend.
 */
export async function logout(): Promise<void> {
  const cookieStore = await cookies();

  try {
    // Call backend logout
    await fetch(`${env.apiBaseUrl}/auth/logout`, {
      method: "POST",
      credentials: "include",
    });
  } catch {
    // Continue even if backend call fails
  }

  // Clear all auth cookies
  cookieStore.delete("access_token_cookie");
  cookieStore.delete("refresh_token_cookie");
  cookieStore.delete("csrf_access_token");
  cookieStore.delete("csrf_refresh_token");

  redirect("/login");
}

/**
 * Refresh token server action.
 */
export async function refreshToken(): Promise<boolean> {
  try {
    const response = await fetch(`${env.apiBaseUrl}/auth/refresh`, {
      method: "POST",
      credentials: "include",
    });

    if (!response.ok) {
      return false;
    }

    // Forward new cookies
    const setCookieHeaders = response.headers.getSetCookie();
    const cookieStore = await cookies();

    for (const cookie of setCookieHeaders) {
      const [nameValue] = cookie.split(";");
      const [name, value] = nameValue.split("=");
      cookieStore.set(name, value, {
        httpOnly: true,
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax",
        path: "/",
      });
    }

    return true;
  } catch {
    return false;
  }
}
```

### Step 4: Create Middleware

**`src/middleware.ts`**
```typescript
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

// Routes that require authentication
const protectedRoutes = ["/dashboard", "/projects", "/settings"];

// Routes that should redirect to dashboard if authenticated
const authRoutes = ["/login"];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Check for access token cookie
  const accessToken = request.cookies.get("access_token_cookie")?.value;
  const isAuthenticated = !!accessToken;

  // Redirect authenticated users away from auth pages
  if (isAuthenticated && authRoutes.some((route) => pathname.startsWith(route))) {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }

  // Redirect unauthenticated users to login
  if (!isAuthenticated && protectedRoutes.some((route) => pathname.startsWith(route))) {
    const loginUrl = new URL("/login", request.url);
    loginUrl.searchParams.set("callbackUrl", pathname);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match all paths except:
     * - _next/static (static files)
     * - _next/image (image optimization)
     * - favicon.ico (favicon)
     * - public folder
     */
    "/((?!_next/static|_next/image|favicon.ico|public).*)",
  ],
};
```

### Step 5: Create Auth Context (Client)

**`src/context/AuthContext.tsx`**
```typescript
"use client";

import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import type { User, AuthState, LoginCredentials } from "@/lib/auth/types";
import { login as loginAction, logout as logoutAction } from "@/lib/auth/actions";

interface AuthContextType extends AuthState {
  login: (credentials: LoginCredentials) => Promise<{ success: boolean; error?: string }>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

interface AuthProviderProps {
  children: ReactNode;
  initialUser?: User | null;
}

export function AuthProvider({ children, initialUser = null }: AuthProviderProps) {
  const router = useRouter();
  const [state, setState] = useState<AuthState>({
    user: initialUser,
    isAuthenticated: !!initialUser,
    isLoading: false,
  });

  const login = useCallback(async (credentials: LoginCredentials) => {
    setState((prev) => ({ ...prev, isLoading: true }));

    const result = await loginAction(credentials);

    if (result.success && result.user) {
      setState({
        user: result.user,
        isAuthenticated: true,
        isLoading: false,
      });
      router.push("/dashboard");
      router.refresh();
      return { success: true };
    }

    setState((prev) => ({ ...prev, isLoading: false }));
    return { success: false, error: result.error };
  }, [router]);

  const logout = useCallback(async () => {
    setState((prev) => ({ ...prev, isLoading: true }));
    await logoutAction();
    setState({
      user: null,
      isAuthenticated: false,
      isLoading: false,
    });
  }, []);

  return (
    <AuthContext.Provider
      value={{
        ...state,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
```

### Step 6: Update API Client

**Update `src/lib/api/http.ts`**
```typescript
// Add credentials: "include" to all requests
const response = await fetch(url, {
  method,
  headers: { ...defaultHeaders, ...headers },
  body: body ? JSON.stringify(body) : undefined,
  signal,
  credentials: "include", // <-- ADD THIS
});
```

### Step 7: Update Root Layout

**Update `src/app/layout.tsx`**
```typescript
import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { AuthProvider } from "@/context/AuthContext";
import { getCurrentUser } from "@/lib/auth/session";

// ... fonts

export const metadata: Metadata = {
  title: "Construction Management",
  description: "Construction project management system",
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const user = await getCurrentUser();

  return (
    <html lang="en">
      <body className={`${geistSans.variable} ${geistMono.variable} antialiased`}>
        <AuthProvider initialUser={user}>
          {children}
        </AuthProvider>
      </body>
    </html>
  );
}
```

## Todo List

- [x] Create auth TypeScript types
- [x] Create server-side session utilities
- [x] Create login/logout server actions
- [x] Create Next.js middleware
- [x] Create AuthContext and AuthProvider
- [x] Update API client with credentials:include
- [x] Update root layout with AuthProvider
- [ ] Test middleware redirects (Phase 06)
- [ ] Test server action cookies (Phase 06)

## Code Review Notes (260118-2046)

**Score: 8/10 -> 9/10 (after fixes)**

**All issues resolved:**
- Cookie parsing: FIXED (parseCookie uses indexOf)
- LoginResponse type: FIXED (added token_type, expires_in)
- middleware.ts: FIXED (created with helpers)
- logout dead code: FIXED (Promise<never>)
- JWT expiry: ADDED (decodeJwtPayload)
- Error boundary: ADDED (AuthErrorBoundary)

**Build:** Passes cleanly

See: [Code Review Report](reports/code-reviewer-260118-2046-phase04-frontend-auth-infra.md)

## Success Criteria

- [ ] Middleware redirects unauthenticated to /login
- [ ] Middleware redirects authenticated from /login to /dashboard
- [ ] Server actions set/clear cookies correctly
- [ ] AuthContext provides user state to client components
- [ ] getSession() works in Server Components
- [ ] API requests include cookies automatically

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cookie not forwarded | Medium | High | Test credentials:include |
| SSR hydration mismatch | Medium | Medium | Pass initial user to provider |
| Middleware loop | Low | High | Careful route matching |

## Security Considerations

- Never expose tokens in client-side code
- Use httpOnly cookies only
- Verify auth in Server Components, not just middleware
- Server Actions must re-verify auth

## Next Steps

After this phase:
→ [Phase 05: Frontend Login UI](phase-05-frontend-login-ui.md)
