# Frontend Patterns Research Report
**Construction Management System** | 2026-02-01

## 1. Page Structure Pattern

**File:** `/Users/sweet-home/Works/construction/construction-front-end/src/app/[locale]/(app)/projects/page.tsx`

- Uses `"use client"` for client-side rendering
- App Router with i18n locale segment: `[locale]/(app)`
- Typical structure:
  ```tsx
  "use client"
  import { useTranslations } from "next-intl"
  import { useProject } from "@/context/ProjectContext"
  import { useAuth } from "@/context/AuthContext"
  // UI imports from @/components/ui

  export default function PageName() { ... }
  ```

## 2. API Client Pattern

**File:** `/Users/sweet-home/Works/construction/construction-front-end/src/lib/api/http.ts`

Typed fetch wrapper with auto-retry on 401:
```tsx
// Usage examples
api.get<ResponseType>(endpoint, options)
api.post<ResponseType, BodyType>(endpoint, body, options)
api.patch<ResponseType, BodyType>(endpoint, body, options)
api.delete<ResponseType>(endpoint, options)
```

Key features:
- Bearer token auth via `Authorization` header
- Auto-refresh on 401 (single retry)
- Custom `ApiError` class with status & data
- Credentials: include for cookie-based auth

## 3. Context & State Management

**ProjectContext:** `/src/context/ProjectContext.tsx`
```tsx
interface ProjectContextType {
  projects: Project[]
  selectedProjectId: string | null
  selectedProject: Project | null
  selectProject: (projectId: string) => void
  isLoading: boolean
  error: string | null
  refetch: () => Promise<void>
}

export function useProject() { /* hook */ }
```

- Persists selected project to localStorage
- Auto-fetches projects on mount
- Hydration check to prevent SSR mismatch

**AuthContext:** `/src/context/AuthContext.tsx` (provides user & permissions)

## 4. Available Shadcn UI Components

Located: `/src/components/ui/`

- `button.tsx` - Button component
- `card.tsx` - Card/CardContent
- `badge.tsx` - Badge
- `alert.tsx` - Alert/AlertDescription
- `alert-dialog.tsx` - AlertDialog (confirm dialogs)
- `dialog.tsx` - Dialog/modal
- `input.tsx` - Text input
- `label.tsx` - Form label
- `select.tsx` - Select dropdown
- `dropdown-menu.tsx` - Dropdown menu
- `separator.tsx` - Visual separator

## 5. i18n Translation Pattern

**Namespace structure:** `t("projects.title")`

Translation keys accessed via:
```tsx
const t = useTranslations("projects")
t("title") // projects.title
t("description")
t("newProject")
t("teamMembers")
t("addMember")
t("removeMemberTitle")
```

Key convention: `namespace.key` with camelCase keys

## 6. Component Patterns

**Import structure:**
```tsx
import { Plus, Building2, Users, Check, Loader2, ChevronDown } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { useTranslations } from "next-intl"
```

**Loading/Error/Empty states:**
- Loading: `<Loader2 className="animate-spin" />`
- Error: `<Alert variant="destructive">`
- Empty: Card with centered icon + message

**Permission checks:**
```tsx
const canManageUsers = user?.permissions?.some(
  (p) => p === "project:manage_users" || p === "*:*"
) ?? false
```

## 7. Key Implementation Paths

- API functions: `/src/lib/api/projects.ts` (fetchProjects, fetchProjectUsers, removeUserFromProject)
- Types: `/src/types/project.ts` (Project, ProjectUser)
- Dialogs: `/src/components/project/add-member-dialog.tsx`

## Labor Charge Feature Recommendations

For implementing labor charge feature:
1. Create `/src/lib/api/labor-charges.ts` with http methods
2. Extend `/src/context/ProjectContext.tsx` or create new `LaborChargeContext`
3. Use dialog pattern from `AddMemberDialog` for forms
4. Translation keys: `t("laborCharges.title")`, `t("laborCharges.addCharge")`
5. Component: `/src/components/labor-charges/labor-charge-form.tsx`
6. Type: `/src/types/labor-charge.ts`

**Unresolved Questions:**
- Where is messages/translations file located? (Not found at expected path)
- Exact endpoint paths for labor charges API?
- Should labor charges be nested under project context or separate?
