---
title: "Project Management Feature"
description: "CRUD API and frontend selector for construction projects"
status: pending
priority: P2
effort: 8h
branch: main
tags: [feature, projects, crud, frontend, backend]
created: 2026-01-24
---

# Project Management Feature

## Overview

Enable users to view/switch construction projects; admins can create/edit/delete.

**Data Model:** Project (name, address, created_at, owner_id) + many-to-many user association.

## Phase Summary

| Phase | Description | Effort | Status |
|-------|-------------|--------|--------|
| [01](./phase-01-database-models.md) | Database models & migration | 1h | pending |
| [02](./phase-02-backend-domain-layer.md) | Domain entities & exceptions | 0.5h | pending |
| [03](./phase-03-backend-application-layer.md) | Use cases & ports | 1h | pending |
| [04](./phase-04-backend-api-endpoints.md) | REST endpoints & RBAC | 1.5h | pending |
| [05](./phase-05-frontend-context.md) | ProjectContext + localStorage | 1h | pending |
| [06](./phase-06-frontend-components.md) | ProjectSelector in Topbar | 1.5h | pending |
| [07](./phase-07-testing.md) | Backend & frontend tests | 1.5h | pending |

## Key Dependencies

- Existing: `UserModel`, `RoleModel`, `PermissionModel`
- Existing: `AuthContext`, `Topbar`, RBAC decorators
- New permissions: `project:create`, `project:read`, `project:update`, `project:delete`

## Architecture

```
Frontend                          Backend
---------                         --------
ProjectContext ─────────────────► /api/v1/projects (CRUD)
  └─ localStorage                      │
  └─ ProjectSelector                   ▼
                                  ProjectRepository
                                       │
                                       ▼
                                  ProjectModel + user_projects
```

## Research Reports

- [Backend Patterns](./research/researcher-backend-patterns.md)
- [Frontend Patterns](./research/researcher-frontend-patterns.md)

## Success Criteria

1. Users can view and switch projects via Topbar dropdown
2. Selection persists in localStorage across sessions
3. Admins can CRUD projects via API
4. Non-admins get 403 on write operations
5. Tests cover happy path + permission denial

## Risks

- **Hydration mismatch**: Mitigate with `isHydrated` flag
- **N+1 queries**: Use `joinedload()` for user associations
- **Permission leakage**: Verify RBAC at route level, not just UI
