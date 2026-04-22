# Phase 01: Database Models & Migration

## Context Links

- [Backend Patterns Research](./research/researcher-backend-patterns.md)
- [Existing Models](../../construction-back-end/app/infrastructure/database/models.py)
- [Auth Migration Example](../../construction-back-end/migrations/versions/7f6bfdbaee86_create_auth_tables_for_users_roles_and_.py)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 1h |

Create `ProjectModel` and `user_projects` association table following existing SQLAlchemy patterns.

## Key Insights

- Follow existing `user_roles` association table pattern
- Use `UUID(as_uuid=True)` for primary keys
- Add `assigned_at` timestamp for audit trail
- `joinedload()` required to prevent N+1 on `project.users`

## Requirements

### Functional
- `projects` table: id, name, address, owner_id, created_at, updated_at
- `user_projects` junction table: user_id, project_id, assigned_at
- Many-to-many relationship between users and projects
- Owner reference (one-to-many from user to owned projects)

### Non-Functional
- UUID primary keys for distributed ID generation
- Indexes on foreign keys for query performance
- Cascade delete on user_projects when project deleted

## Architecture

```
users (existing)
  │
  ├── owns ──────────► projects (owner_id FK)
  │                      │
  └── assigned ◄─────► user_projects ◄─────► projects
        (M:N)
```

## Related Code Files

### Modify
- `construction-back-end/app/infrastructure/database/models.py`

### Create
- `construction-back-end/migrations/versions/XXXXXX_add_projects_table.py`

## Implementation Steps

1. **Add association table to models.py**
   ```python
   user_projects = Table(
       "user_projects",
       Base.metadata,
       Column("user_id", UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
       Column("project_id", UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), primary_key=True),
       Column("assigned_at", DateTime, default=lambda: datetime.now(timezone.utc)),
   )
   ```

2. **Add ProjectModel class**
   ```python
   class ProjectModel(Base):
       __tablename__ = "projects"

       id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
       name = Column(String(255), nullable=False)
       address = Column(String(500), nullable=True)
       owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
       created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
       updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

       # Relationships
       owner = relationship("UserModel", foreign_keys=[owner_id])
       users = relationship("UserModel", secondary=user_projects, back_populates="projects")
   ```

3. **Add back-reference on UserModel**
   ```python
   # In UserModel class
   projects = relationship("ProjectModel", secondary=user_projects, back_populates="users")
   ```

4. **Generate Alembic migration**
   ```bash
   cd construction-back-end
   alembic revision --autogenerate -m "add projects table and user_projects association"
   ```

5. **Review & run migration**
   ```bash
   alembic upgrade head
   ```

## Todo List

- [ ] Add `user_projects` association table to models.py
- [ ] Add `ProjectModel` class with all columns
- [ ] Add `projects` relationship to `UserModel`
- [ ] Generate Alembic migration
- [ ] Review migration SQL for correctness
- [ ] Run migration against dev database
- [ ] Verify tables created via `psql` or DB tool

## Success Criteria

1. `projects` table exists with correct schema
2. `user_projects` junction table exists with composite PK
3. Foreign key constraints enforced
4. Indexes created on foreign keys
5. SQLAlchemy relationships work bidirectionally

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Migration conflict with existing | Medium | Check `down_revision` chain |
| Circular import in models | Low | Use `TYPE_CHECKING` pattern |
| Missing index on owner_id | Low | Add explicit index |

## Security Considerations

- No sensitive data in project table (address is construction site, not user address)
- Cascade delete prevents orphaned records
- UUID prevents enumeration attacks

## Next Steps

After completion:
1. Proceed to Phase 02 (Domain entities)
2. Seed test data for development
