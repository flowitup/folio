# Phase 05: Frontend Context (ProjectContext)

## Context Links

- [Frontend Patterns Research](./research/researcher-frontend-patterns.md)
- [Existing AuthContext](../../construction-front-end/src/context/AuthContext.tsx)
- [Root Layout](../../construction-front-end/src/app/layout.tsx)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 1h |

Create ProjectContext with localStorage persistence for selected project, following existing AuthContext pattern.

## Key Insights

- localStorage only accessible client-side (useEffect pattern)
- `isHydrated` flag prevents SSR/hydration mismatch
- Context placed below AuthProvider (project selection requires auth)
- Fetch projects via React Query or SWR

## Requirements

### Functional
- Store `selectedProjectId` in localStorage
- Load persisted selection on mount
- Expose `selectProject(id)` method
- Expose `projects` list from API
- Expose `selectedProject` derived value

### Non-Functional
- No hydration warnings
- TypeScript types for context
- Loading states during fetch
- Error handling for invalid stored ID

## Architecture

```
src/
├── context/
│   └── ProjectContext.tsx    # Provider + hook
├── lib/
│   └── api/
│       └── projects.ts       # API fetch functions
└── types/
    └── project.ts            # TypeScript types
```

## Related Code Files

### Create
- `construction-front-end/src/context/ProjectContext.tsx`
- `construction-front-end/src/lib/api/projects.ts`
- `construction-front-end/src/types/project.ts`

### Modify
- `construction-front-end/src/app/layout.tsx` (add ProjectProvider)

## Implementation Steps

### 1. Create TypeScript Types

File: `src/types/project.ts`
```typescript
export interface Project {
  id: string;
  name: string;
  address: string | null;
  owner_id: string;
  user_count: number;
  created_at: string;
}

export interface ProjectListResponse {
  projects: Project[];
  total: number;
}
```

### 2. Create API Functions

File: `src/lib/api/projects.ts`
```typescript
import type { Project, ProjectListResponse } from "@/types/project";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:5000";

export async function fetchProjects(): Promise<Project[]> {
  const res = await fetch(`${API_BASE}/api/v1/projects`, {
    credentials: "include", // Include cookies for JWT
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch projects: ${res.status}`);
  }

  const data: ProjectListResponse = await res.json();
  return data.projects;
}

export async function fetchProjectById(id: string): Promise<Project> {
  const res = await fetch(`${API_BASE}/api/v1/projects/${id}`, {
    credentials: "include",
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch project: ${res.status}`);
  }

  return res.json();
}
```

### 3. Create ProjectContext

File: `src/context/ProjectContext.tsx`
```typescript
"use client";

import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  type ReactNode,
} from "react";
import type { Project } from "@/types/project";
import { fetchProjects } from "@/lib/api/projects";

const STORAGE_KEY = "selectedProjectId";

interface ProjectContextType {
  projects: Project[];
  selectedProjectId: string | null;
  selectedProject: Project | null;
  selectProject: (projectId: string) => void;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

const ProjectContext = createContext<ProjectContextType | undefined>(undefined);

interface ProjectProviderProps {
  children: ReactNode;
}

export function ProjectProvider({ children }: ProjectProviderProps) {
  const [projects, setProjects] = useState<Project[]>([]);
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);
  const [isHydrated, setIsHydrated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Load from localStorage on mount (client-only)
  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    setSelectedProjectId(stored);
    setIsHydrated(true);
  }, []);

  // Persist to localStorage on change
  useEffect(() => {
    if (isHydrated) {
      if (selectedProjectId) {
        localStorage.setItem(STORAGE_KEY, selectedProjectId);
      } else {
        localStorage.removeItem(STORAGE_KEY);
      }
    }
  }, [selectedProjectId, isHydrated]);

  // Fetch projects
  const loadProjects = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const data = await fetchProjects();
      setProjects(data);

      // If stored ID is invalid, clear it
      if (selectedProjectId && !data.find((p) => p.id === selectedProjectId)) {
        setSelectedProjectId(null);
      }

      // Auto-select first project if none selected
      if (!selectedProjectId && data.length > 0) {
        setSelectedProjectId(data[0].id);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load projects");
    } finally {
      setIsLoading(false);
    }
  }, [selectedProjectId]);

  // Fetch on mount and when hydrated
  useEffect(() => {
    if (isHydrated) {
      loadProjects();
    }
  }, [isHydrated, loadProjects]);

  const selectProject = useCallback((projectId: string) => {
    setSelectedProjectId(projectId);
  }, []);

  const selectedProject = projects.find((p) => p.id === selectedProjectId) ?? null;

  // Don't render until hydrated to prevent mismatch
  if (!isHydrated) {
    return <>{children}</>;
  }

  return (
    <ProjectContext.Provider
      value={{
        projects,
        selectedProjectId,
        selectedProject,
        selectProject,
        isLoading,
        error,
        refetch: loadProjects,
      }}
    >
      {children}
    </ProjectContext.Provider>
  );
}

export function useProject() {
  const context = useContext(ProjectContext);
  if (context === undefined) {
    throw new Error("useProject must be used within ProjectProvider");
  }
  return context;
}
```

### 4. Update Root Layout

File: `src/app/layout.tsx` - Add ProjectProvider:
```typescript
import { ProjectProvider } from "@/context/ProjectContext";

// In the return JSX:
<AuthErrorBoundary>
  <AuthProvider initialUser={user}>
    <ProjectProvider>
      {children}
    </ProjectProvider>
  </AuthProvider>
</AuthErrorBoundary>
```

## Todo List

- [ ] Create `src/types/project.ts`
- [ ] Create `src/lib/api/projects.ts`
- [ ] Create `src/context/ProjectContext.tsx`
- [ ] Update `src/app/layout.tsx` with ProjectProvider
- [ ] Verify no hydration warnings in browser console
- [ ] Test localStorage persistence across page refresh

## Success Criteria

1. `useProject()` hook works in client components
2. `selectedProjectId` persists in localStorage
3. Projects fetched from API on mount
4. No SSR hydration mismatches
5. Invalid stored ID gracefully handled

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Hydration mismatch | High | `isHydrated` flag + useEffect |
| Race condition fetch | Medium | Loading state + proper deps |
| Auth required for fetch | Medium | Fetch after AuthProvider mounts |

## Security Considerations

- localStorage stores only project ID (not sensitive)
- API fetch includes credentials for auth
- Invalid ID doesn't expose data

## Next Steps

After completion:
1. Proceed to Phase 06 (ProjectSelector component)
2. Verify context available throughout app
