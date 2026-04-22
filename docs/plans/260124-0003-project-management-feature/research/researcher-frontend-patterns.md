# Next.js 16 App Router Global State & Project Selection - Research Report

**Date:** 2026-01-24
**Focus:** Context patterns, localStorage persistence, component integration
**Target:** ProjectContext implementation for project selector

---

## 1. Context with localStorage Persistence Pattern

### Challenge
localStorage is browser-only; SSR/hydration mismatch causes errors.

### Solution: useEffect-Based Initialization

```typescript
"use client";

import { createContext, useContext, useState, useEffect, ReactNode } from "react";

interface ProjectContextType {
  selectedProjectId: string | null;
  selectProject: (projectId: string) => void;
}

const ProjectContext = createContext<ProjectContextType | undefined>(undefined);

export function ProjectProvider({ children }: { children: ReactNode }) {
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);
  const [isHydrated, setIsHydrated] = useState(false);

  // Load from localStorage on mount (client-only)
  useEffect(() => {
    const stored = localStorage.getItem("selectedProjectId");
    setSelectedProjectId(stored);
    setIsHydrated(true);
  }, []);

  // Persist to localStorage on change
  useEffect(() => {
    if (isHydrated && selectedProjectId) {
      localStorage.setItem("selectedProjectId", selectedProjectId);
    }
  }, [selectedProjectId, isHydrated]);

  const selectProject = (projectId: string) => {
    setSelectedProjectId(projectId);
  };

  // Don't render until hydrated to prevent mismatch
  if (!isHydrated) {
    return <>{children}</>;
  }

  return (
    <ProjectContext.Provider value={{ selectedProjectId, selectProject }}>
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

**Key Points:**
- `useEffect` avoids localStorage access during SSR
- `isHydrated` flag prevents render mismatches
- Two useEffect hooks: read on mount, write on change
- Follows existing AuthContext pattern in your codebase

---

## 2. Next.js 16 Layout Composition

### Recommended Placement

```typescript
// src/app/layout.tsx (root layout)
import { AuthProvider } from "@/context/AuthContext";
import { ProjectProvider } from "@/context/ProjectContext";
import { AuthErrorBoundary } from "@/context/AuthErrorBoundary";

export default async function RootLayout({ children }) {
  const user = await getCurrentUser();

  return (
    <html lang="en">
      <body>
        <AuthErrorBoundary>
          <AuthProvider initialUser={user}>
            <ProjectProvider>
              {children}
            </ProjectProvider>
          </AuthProvider>
        </AuthErrorBoundary>
      </body>
    </html>
  );
}
```

**Best Practice:** Render providers as deep as possible in tree to preserve static Server Component optimization.

---

## 3. Server + Client Component Interleaving

Layout structure allowing Topbar (client) with nested Server Components:

```typescript
// src/app/(app)/layout.tsx (server component)
export default async function AppLayout({ children }) {
  const session = await getSession();
  if (!session) redirect("/login");

  return (
    <div className="flex h-screen">
      <Sidebar /> {/* Server or Client Component */}
      <div className="flex flex-1 flex-col">
        <Topbar /> {/* Client Component - uses Context */}
        <main>{children}</main> {/* Server Components */}
      </div>
    </div>
  );
}
```

**Key:** Topbar can consume ProjectContext even with Server Components as siblings/children.

---

## 4. ProjectSelector Dropdown Component

### Option A: Using shadcn/ui Select

```typescript
"use client";

import { useProject } from "@/context/ProjectContext";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useQuery } from "@tanstack/react-query";

interface Project {
  id: string;
  name: string;
}

export function ProjectSelector() {
  const { selectedProjectId, selectProject } = useProject();
  const { data: projects = [] } = useQuery({
    queryKey: ["projects"],
    queryFn: async () => {
      const res = await fetch("/api/projects");
      return res.json();
    },
  });

  return (
    <Select value={selectedProjectId || ""} onValueChange={selectProject}>
      <SelectTrigger className="w-48">
        <SelectValue placeholder="Select project..." />
      </SelectTrigger>
      <SelectContent>
        {projects.map((project: Project) => (
          <SelectItem key={project.id} value={project.id}>
            {project.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
```

### Option B: Minimal Custom Dropdown

```typescript
"use client";

import { useProject } from "@/context/ProjectContext";
import { useState } from "react";

export function ProjectSelector() {
  const { selectedProjectId, selectProject } = useProject();
  const [isOpen, setIsOpen] = useState(false);
  const [projects, setProjects] = useState<Array<{ id: string; name: string }>>([]);

  // Load projects on mount
  useEffect(() => {
    fetch("/api/projects")
      .then(res => res.json())
      .then(setProjects);
  }, []);

  return (
    <div className="relative">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="px-3 py-2 bg-white border rounded-md text-sm font-medium"
      >
        {projects.find(p => p.id === selectedProjectId)?.name || "Select..."}
      </button>
      {isOpen && (
        <div className="absolute top-10 left-0 bg-white border rounded-md shadow-lg z-10">
          {projects.map(project => (
            <button
              key={project.id}
              onClick={() => {
                selectProject(project.id);
                setIsOpen(false);
              }}
              className="block w-full text-left px-4 py-2 hover:bg-gray-100"
            >
              {project.name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

---

## 5. Topbar Integration

```typescript
// src/components/layout/Topbar.tsx
"use client";

import { useAuth } from "@/context/AuthContext";
import { ProjectSelector } from "@/components/project/ProjectSelector";

export function Topbar() {
  const { user, logout, isLoading } = useAuth();

  return (
    <header className="flex h-16 items-center justify-between border-b border-gray-200 bg-white px-6">
      <div className="flex items-center gap-4">
        <h1 className="text-lg font-semibold text-gray-900">Dashboard</h1>
        <ProjectSelector /> {/* NEW: Project selector */}
      </div>

      {/* Right side unchanged */}
      <div className="flex items-center gap-4">
        <button className="rounded-full p-2 text-gray-500 hover:bg-gray-100">
          🔔
        </button>
        {user && (
          <div className="flex items-center gap-3">
            <div className="h-8 w-8 rounded-full bg-blue-500 flex items-center justify-center">
              <span className="text-sm font-medium text-white">
                {user.email.charAt(0).toUpperCase()}
              </span>
            </div>
            <span className="text-sm font-medium text-gray-700">{user.email}</span>
            <button
              onClick={() => logout()}
              disabled={isLoading}
              className="rounded-md bg-gray-100 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200"
            >
              {isLoading ? "..." : "Sign out"}
            </button>
          </div>
        )}
      </div>
    </header>
  );
}
```

---

## 6. Key Implementation Notes

**Hydration Safety:**
- Wrap localStorage in useEffect
- Use isHydrated flag to avoid render mismatch
- Delay context provider value until hydrated

**Performance:**
- Keep ProjectProvider high in tree but below root
- Use React.memo() for ProjectSelector if frequently re-rendered
- Lazy-load projects list via React Query or SWR

**State Sync:**
- Write to localStorage only on explicit user action
- Read from localStorage on mount
- Consider Context + localStorage pattern as "last selected"

**TypeScript:**
- Define ProjectContextType interface for type safety
- Import Project type from API types
- Handle null selectedProjectId gracefully

---

## Unresolved Questions

1. Should selected project auto-load dashboard data? (Requires integration with data fetching layer)
2. Multi-tenant isolation - validate API returns only accessible projects per user?
3. Fallback behavior if localStorage corrupted or selectedProjectId invalid?

---

## Sources

- [Next.js Server and Client Components](https://nextjs.org/docs/app/getting-started/server-and-client-components)
- [Client Context Example - Next.js Playground](https://app-router.vercel.app/context)
- [Next.js 16 Release Blog](https://nextjs.org/blog/next-16)
- [React Context State Management in Next.js - Vercel](https://vercel.com/kb/guide/react-context-state-management-nextjs)
- [How to use Local Storage in Next.js](https://dev.to/collegewap/how-to-use-local-storage-in-next-js-2l2j)
- [Persisting State with localStorage in Next.js](https://dev.to/jaklaudiusz/next-js-persistent-state-with-react-hooks-and-localstorage-how-to-make-it-work-3al6)
- [shadcn/ui Select Component](https://ui.shadcn.com/docs/components/select)
- [shadcn/ui Dropdown Menu](https://ui.shadcn.com/docs/components/dropdown-menu)
