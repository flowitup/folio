# Phase 06: Frontend Components (ProjectSelector)

## Context Links

- [Frontend Patterns Research](./research/researcher-frontend-patterns.md)
- [Existing Topbar](../../construction-front-end/src/components/layout/Topbar.tsx)
- [Existing Sidebar](../../construction-front-end/src/components/layout/Sidebar.tsx)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 1.5h |

Create ProjectSelector dropdown component and integrate into Topbar (top-left position).

## Key Insights

- Use native `<select>` or custom dropdown (keep simple - KISS)
- Position left of page title in Topbar
- Show loading state while fetching
- Admin-only: show "Manage Projects" link

## Requirements

### Functional
- Dropdown shows all user's projects
- Current selection highlighted
- Changing selection updates context
- Loading spinner during fetch
- Error state if fetch fails

### Non-Functional
- Accessible (keyboard navigation, ARIA)
- Responsive (mobile-friendly)
- Consistent with existing UI (Tailwind classes)

## Architecture

```
components/
├── layout/
│   └── Topbar.tsx           # Modified - add ProjectSelector
└── project/
    └── ProjectSelector.tsx   # New dropdown component
```

## Related Code Files

### Create
- `construction-front-end/src/components/project/ProjectSelector.tsx`

### Modify
- `construction-front-end/src/components/layout/Topbar.tsx`

## Implementation Steps

### 1. Create ProjectSelector Component

File: `src/components/project/ProjectSelector.tsx`
```typescript
"use client";

import { useProject } from "@/context/ProjectContext";

export function ProjectSelector() {
  const {
    projects,
    selectedProjectId,
    selectedProject,
    selectProject,
    isLoading,
    error,
  } = useProject();

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 text-sm text-gray-500">
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-gray-300 border-t-blue-500" />
        Loading...
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-sm text-red-500" title={error}>
        Failed to load projects
      </div>
    );
  }

  if (projects.length === 0) {
    return (
      <div className="text-sm text-gray-500">
        No projects available
      </div>
    );
  }

  return (
    <div className="relative">
      <label htmlFor="project-selector" className="sr-only">
        Select project
      </label>
      <select
        id="project-selector"
        value={selectedProjectId || ""}
        onChange={(e) => selectProject(e.target.value)}
        className="block w-48 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
      >
        {projects.map((project) => (
          <option key={project.id} value={project.id}>
            {project.name}
          </option>
        ))}
      </select>
    </div>
  );
}
```

### 2. Alternative: Custom Dropdown (if more control needed)

File: `src/components/project/ProjectSelectorDropdown.tsx`
```typescript
"use client";

import { useState, useRef, useEffect } from "react";
import { useProject } from "@/context/ProjectContext";

export function ProjectSelectorDropdown() {
  const {
    projects,
    selectedProjectId,
    selectedProject,
    selectProject,
    isLoading,
  } = useProject();

  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Close on Escape
  useEffect(() => {
    function handleEscape(event: KeyboardEvent) {
      if (event.key === "Escape") setIsOpen(false);
    }
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, []);

  if (isLoading) {
    return <div className="text-sm text-gray-500">Loading projects...</div>;
  }

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
        aria-haspopup="listbox"
        aria-expanded={isOpen}
      >
        <span className="truncate max-w-[140px]">
          {selectedProject?.name || "Select project"}
        </span>
        <svg
          className={`h-4 w-4 text-gray-400 transition-transform ${isOpen ? "rotate-180" : ""}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div
          className="absolute left-0 top-full z-10 mt-1 w-56 rounded-md border border-gray-200 bg-white shadow-lg"
          role="listbox"
        >
          <ul className="max-h-60 overflow-auto py-1">
            {projects.map((project) => (
              <li
                key={project.id}
                role="option"
                aria-selected={project.id === selectedProjectId}
                className={`cursor-pointer px-4 py-2 text-sm hover:bg-gray-100 ${
                  project.id === selectedProjectId
                    ? "bg-blue-50 text-blue-700"
                    : "text-gray-700"
                }`}
                onClick={() => {
                  selectProject(project.id);
                  setIsOpen(false);
                }}
              >
                <div className="font-medium">{project.name}</div>
                {project.address && (
                  <div className="text-xs text-gray-500 truncate">{project.address}</div>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
```

### 3. Update Topbar Component

File: `src/components/layout/Topbar.tsx`
```typescript
"use client";

import { useAuth } from "@/context/AuthContext";
import { ProjectSelector } from "@/components/project/ProjectSelector";

export function Topbar() {
  const { user, logout, isLoading } = useAuth();

  return (
    <header className="flex h-16 items-center justify-between border-b border-gray-200 bg-white px-6">
      {/* Left side - Project selector + Page title */}
      <div className="flex items-center gap-4">
        <ProjectSelector />
        <div className="h-6 w-px bg-gray-200" /> {/* Divider */}
        <h1 className="text-lg font-semibold text-gray-900">Dashboard</h1>
      </div>

      {/* Right side - user menu (unchanged) */}
      <div className="flex items-center gap-4">
        {/* Notifications */}
        <button
          className="rounded-full p-2 text-gray-500 hover:bg-gray-100"
          aria-label="View notifications"
        >
          <span aria-hidden="true">🔔</span>
        </button>

        {/* User info and logout */}
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
              className="rounded-md bg-gray-100 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
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

## Todo List

- [ ] Create `src/components/project/` directory
- [ ] Create `ProjectSelector.tsx` component
- [ ] Update `Topbar.tsx` to include ProjectSelector
- [ ] Test dropdown keyboard navigation
- [ ] Test mobile responsiveness
- [ ] Verify localStorage updates on selection change

## Success Criteria

1. Dropdown renders in Topbar left side
2. All user projects listed
3. Selection change updates context + localStorage
4. Loading state shown during fetch
5. Accessible via keyboard (Tab, Enter, Arrow keys)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Z-index conflict | Low | Use proper stacking context |
| Mobile overflow | Medium | Test on small screens |
| Race with auth | Low | ProjectProvider nested inside AuthProvider |

## Security Considerations

- No sensitive data displayed in dropdown
- Project IDs are UUIDs (non-enumerable)
- Selection stored client-side only

## Next Steps

After completion:
1. Proceed to Phase 07 (Testing)
2. Optional: Add admin project management page
