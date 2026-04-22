# Code Review: Phase 04 Frontend Auth Infrastructure

**Date:** 2026-01-18 20:46
**Reviewer:** code-reviewer agent
**Score:** 8/10

## Scope
- Files: types.ts, session.ts, actions.ts, index.ts, middleware.ts, AuthContext.tsx, http.ts, layout.tsx
- Lines: ~280
- Focus: Security, Architecture, YAGNI/KISS/DRY

## Overall Assessment
Solid Next.js 15 server-first auth implementation. Security fundamentals correct (httpOnly cookies, server-side verification). Clean separation between server/client concerns.

---

## Critical Issues (MUST FIX)
**None**

---

## Warnings (SHOULD FIX)

### 1. Cookie parsing fragility
**File:** `src/lib/auth/actions.ts` (lines 39-48, 119-128)

`nameValue.split("=")` fails if value contains `=` (e.g., `token=abc=def`)

```typescript
// Current (fragile):
const [name, value] = nameValue.split("=");

// Fix:
const eqIdx = nameValue.indexOf("=");
const name = nameValue.substring(0, eqIdx);
const value = nameValue.substring(eqIdx + 1);
```

### 2. LoginResponse type mismatch
**File:** `src/lib/auth/types.ts`

Plan specifies `token_type`, `expires_in` fields but not in impl. Verify backend contract.

### 3. Missing planned file
**File:** `src/lib/auth/middleware.ts`

Plan specified auth middleware helpers but not created. Verify if needed or update plan.

### 4. logout() state never updates
**File:** `src/context/AuthContext.tsx` (lines 65-72)

`logoutAction()` calls `redirect()` which throws, so `setState()` never runs. Works but misleading.

---

## Suggestions (NICE TO HAVE)

1. **CSRF token handling** - Currently cleared on logout but not used for POST requests
2. **Session expiry** - Hardcoded 30min in session.ts; could parse from JWT
3. **Error boundary** - If `getCurrentUser()` fails in layout, could crash SSR
4. **Middleware deprecation** - Next.js 16.1 warns about middleware->proxy migration

---

## Positive Observations
- httpOnly cookies only - no token exposure client-side
- Server-first auth verification
- Clean `"use server"` patterns
- `credentials: "include"` correctly added
- Proper hydration with `initialUser`
- callbackUrl preserved for post-login redirect

---

## Todo Completion Status

| Task | Status |
|------|--------|
| Create auth TypeScript types | DONE |
| Create server-side session utilities | DONE |
| Create login/logout server actions | DONE |
| Create Next.js middleware | DONE |
| Create AuthContext and AuthProvider | DONE |
| Update API client | DONE |
| Update root layout | DONE |
| Create middleware.ts helper | MISSING |
| Test middleware redirects | Pending (Phase 06) |
| Test server action cookies | Pending (Phase 06) |

---

## Unresolved Questions
1. Is `src/lib/auth/middleware.ts` needed or should plan be updated?
2. Does backend return `token_type`/`expires_in` fields?
3. Should CSRF tokens be validated on mutations?
