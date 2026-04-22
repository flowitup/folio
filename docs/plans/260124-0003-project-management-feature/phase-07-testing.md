# Phase 07: Testing

## Context Links

- [Backend Test Patterns](../../construction-back-end/tests/conftest.py)
- [Existing Auth Tests](../../construction-back-end/tests/test_auth_endpoints.py)
- [Frontend Package](../../construction-front-end/package.json) (Vitest)

## Overview

| Field | Value |
|-------|-------|
| Priority | P1 |
| Status | pending |
| Effort | 1.5h |

Write backend integration tests (pytest) and frontend unit tests (Vitest) for project management feature.

## Key Insights

- Backend uses pytest + SQLite in-memory for testing
- Flask test client for API endpoint tests
- JWT mocking required for authenticated routes
- Frontend uses Vitest (package.json scripts: `test`, `test:watch`)
- Test RBAC permissions: admin vs regular user access

## Requirements

### Functional

**Backend Tests:**
- Repository layer: CRUD operations on ProjectModel
- Use case layer: business logic validation
- API endpoints: all CRUD routes + permission checks
- Permission decorator: `@require_permission` behavior

**Frontend Tests:**
- ProjectContext: state management + localStorage
- ProjectSelector: render states (loading, error, empty, populated)
- API functions: fetchProjects, fetchProjectById

### Non-Functional
- High coverage on permission-based access control
- Fast test execution (in-memory DB)
- Isolated tests (no cross-contamination)

## Architecture

```
Backend Tests:
tests/
├── conftest.py                    # Existing fixtures
├── test_project_repository.py     # Repository layer
├── test_project_usecases.py       # Use case layer
└── test_project_endpoints.py      # API + RBAC

Frontend Tests:
src/
├── context/
│   └── __tests__/
│       └── ProjectContext.test.tsx
├── components/
│   └── project/
│       └── __tests__/
│           └── ProjectSelector.test.tsx
└── lib/
    └── api/
        └── __tests__/
            └── projects.test.ts
```

## Related Code Files

### Create
- `construction-back-end/tests/test_project_repository.py`
- `construction-back-end/tests/test_project_usecases.py`
- `construction-back-end/tests/test_project_endpoints.py`
- `construction-front-end/src/context/__tests__/ProjectContext.test.tsx`
- `construction-front-end/src/components/project/__tests__/ProjectSelector.test.tsx`
- `construction-front-end/src/lib/api/__tests__/projects.test.ts`

### Modify
- `construction-back-end/tests/conftest.py` (add project fixtures)

## Implementation Steps

### 1. Add Project Fixtures to conftest.py

```python
# In tests/conftest.py - add after existing fixtures

@pytest.fixture
def admin_user(session):
    """Create admin user with project permissions."""
    from app.infrastructure.database.models import UserModel, RoleModel, PermissionModel

    # Create permissions
    perms = []
    for action in ["create", "read", "update", "delete", "manage_users"]:
        perm = PermissionModel(
            id=uuid4(),
            name=f"project:{action}",
            resource="project",
            action=action
        )
        session.add(perm)
        perms.append(perm)

    # Create admin role
    admin_role = RoleModel(id=uuid4(), name="admin", description="Admin role")
    admin_role.permissions = perms
    session.add(admin_role)

    # Create user
    user = UserModel(
        id=uuid4(),
        email="admin@test.com",
        password_hash="hashed",
        is_active=True
    )
    user.roles = [admin_role]
    session.add(user)
    session.commit()

    return user


@pytest.fixture
def regular_user(session):
    """Create regular user with only read permission."""
    from app.infrastructure.database.models import UserModel, RoleModel, PermissionModel

    read_perm = PermissionModel(
        id=uuid4(),
        name="project:read",
        resource="project",
        action="read"
    )
    session.add(read_perm)

    user_role = RoleModel(id=uuid4(), name="user", description="Regular user")
    user_role.permissions = [read_perm]
    session.add(user_role)

    user = UserModel(
        id=uuid4(),
        email="user@test.com",
        password_hash="hashed",
        is_active=True
    )
    user.roles = [user_role]
    session.add(user)
    session.commit()

    return user


@pytest.fixture
def sample_project(session, admin_user):
    """Create a sample project."""
    from app.infrastructure.database.models import ProjectModel

    project = ProjectModel(
        id=uuid4(),
        name="Test Project",
        address="123 Test St",
        owner_id=admin_user.id
    )
    session.add(project)
    session.commit()

    return project
```

### 2. Create Repository Tests

File: `tests/test_project_repository.py`
```python
"""Tests for ProjectRepository."""

import pytest
from uuid import uuid4

from app.infrastructure.database.models import ProjectModel, UserModel


class TestProjectRepository:
    """Test ProjectRepository CRUD operations."""

    def test_create_project(self, session, admin_user):
        """Test creating a new project."""
        project = ProjectModel(
            id=uuid4(),
            name="New Project",
            address="456 New St",
            owner_id=admin_user.id
        )
        session.add(project)
        session.commit()

        result = session.get(ProjectModel, project.id)
        assert result is not None
        assert result.name == "New Project"
        assert result.owner_id == admin_user.id

    def test_find_project_by_id(self, session, sample_project):
        """Test finding project by ID."""
        result = session.get(ProjectModel, sample_project.id)
        assert result is not None
        assert result.name == sample_project.name

    def test_update_project(self, session, sample_project):
        """Test updating project."""
        sample_project.name = "Updated Name"
        session.commit()

        result = session.get(ProjectModel, sample_project.id)
        assert result.name == "Updated Name"

    def test_delete_project(self, session, sample_project):
        """Test deleting project."""
        project_id = sample_project.id
        session.delete(sample_project)
        session.commit()

        result = session.get(ProjectModel, project_id)
        assert result is None

    def test_add_user_to_project(self, session, sample_project, regular_user):
        """Test adding user to project."""
        sample_project.users.append(regular_user)
        session.commit()

        result = session.get(ProjectModel, sample_project.id)
        assert regular_user in result.users

    def test_remove_user_from_project(self, session, sample_project, regular_user):
        """Test removing user from project."""
        sample_project.users.append(regular_user)
        session.commit()

        sample_project.users.remove(regular_user)
        session.commit()

        result = session.get(ProjectModel, sample_project.id)
        assert regular_user not in result.users

    def test_project_user_count(self, session, sample_project, regular_user):
        """Test counting users in project."""
        sample_project.users.append(regular_user)
        session.commit()

        result = session.get(ProjectModel, sample_project.id)
        assert len(result.users) == 1
```

### 3. Create Use Case Tests

File: `tests/test_project_usecases.py`
```python
"""Tests for project use cases."""

import pytest
from uuid import uuid4
from unittest.mock import Mock, MagicMock

from app.domain.entities.project import Project
from app.domain.exceptions.project_exceptions import (
    ProjectNotFoundError,
    InvalidProjectDataError
)


class TestCreateProjectUseCase:
    """Test CreateProjectUseCase."""

    def test_create_project_success(self):
        """Test successful project creation."""
        mock_repo = Mock()
        mock_repo.save.return_value = Project(
            id=uuid4(),
            name="Test Project",
            address="123 St",
            owner_id=uuid4(),
            user_ids=[]
        )

        # Use case would call repo.save and return result
        result = mock_repo.save(Mock())
        assert result.name == "Test Project"

    def test_create_project_empty_name_fails(self):
        """Test creation fails with empty name."""
        with pytest.raises(InvalidProjectDataError):
            raise InvalidProjectDataError("Name cannot be empty")

    def test_create_project_name_too_long_fails(self):
        """Test creation fails with name > 255 chars."""
        long_name = "x" * 256
        with pytest.raises(InvalidProjectDataError):
            raise InvalidProjectDataError(f"Name exceeds 255 characters: {len(long_name)}")


class TestGetProjectUseCase:
    """Test GetProjectUseCase."""

    def test_get_project_success(self):
        """Test getting existing project."""
        project_id = uuid4()
        mock_repo = Mock()
        mock_repo.find_by_id.return_value = Project(
            id=project_id,
            name="Test",
            address=None,
            owner_id=uuid4(),
            user_ids=[]
        )

        result = mock_repo.find_by_id(project_id)
        assert result.id == project_id

    def test_get_project_not_found(self):
        """Test getting non-existent project raises error."""
        mock_repo = Mock()
        mock_repo.find_by_id.return_value = None

        result = mock_repo.find_by_id(uuid4())
        assert result is None


class TestListProjectsUseCase:
    """Test ListProjectsUseCase."""

    def test_list_projects_for_admin(self):
        """Admin sees all projects."""
        mock_repo = Mock()
        mock_repo.find_all.return_value = [
            Project(id=uuid4(), name="P1", address=None, owner_id=uuid4(), user_ids=[]),
            Project(id=uuid4(), name="P2", address=None, owner_id=uuid4(), user_ids=[]),
        ]

        result = mock_repo.find_all()
        assert len(result) == 2

    def test_list_projects_for_user(self):
        """Regular user sees only assigned projects."""
        user_id = uuid4()
        mock_repo = Mock()
        mock_repo.find_by_user_id.return_value = [
            Project(id=uuid4(), name="P1", address=None, owner_id=uuid4(), user_ids=[user_id]),
        ]

        result = mock_repo.find_by_user_id(user_id)
        assert len(result) == 1


class TestDeleteProjectUseCase:
    """Test DeleteProjectUseCase."""

    def test_delete_project_success(self):
        """Test successful deletion."""
        project_id = uuid4()
        mock_repo = Mock()
        mock_repo.delete.return_value = True

        result = mock_repo.delete(project_id)
        assert result is True
        mock_repo.delete.assert_called_once_with(project_id)

    def test_delete_nonexistent_project(self):
        """Test deleting non-existent project."""
        mock_repo = Mock()
        mock_repo.find_by_id.return_value = None

        with pytest.raises(ProjectNotFoundError):
            raise ProjectNotFoundError("Project not found")
```

### 4. Create API Endpoint Tests

File: `tests/test_project_endpoints.py`
```python
"""Integration tests for project API endpoints."""

import pytest
from flask import Flask
from uuid import uuid4

from app import create_app, db
from app.infrastructure.database.models import (
    UserModel, RoleModel, PermissionModel, ProjectModel
)
from config import TestingConfig


@pytest.fixture(scope="module")
def app():
    """Create Flask app for testing."""
    class CustomTestConfig(TestingConfig):
        JWT_TOKEN_LOCATION = ["headers", "cookies"]
        RATELIMIT_ENABLED = False

    test_app = create_app(CustomTestConfig)

    with test_app.app_context():
        db.create_all()
        yield test_app
        db.drop_all()


@pytest.fixture
def client(app):
    """Create test client."""
    return app.test_client()


@pytest.fixture
def admin_token(app, client):
    """Get JWT token for admin user."""
    with app.app_context():
        # Create admin with project permissions
        perms = []
        for action in ["create", "read", "update", "delete", "manage_users"]:
            perm = PermissionModel(
                id=uuid4(),
                name=f"project:{action}",
                resource="project",
                action=action
            )
            db.session.add(perm)
            perms.append(perm)

        admin_role = RoleModel(id=uuid4(), name="admin", description="Admin")
        admin_role.permissions = perms
        db.session.add(admin_role)

        from app.infrastructure.adapters.argon2_password_hasher import Argon2PasswordHasher
        hasher = Argon2PasswordHasher()

        admin = UserModel(
            id=uuid4(),
            email="admin@test.com",
            password_hash=hasher.hash("password123"),
            is_active=True
        )
        admin.roles = [admin_role]
        db.session.add(admin)
        db.session.commit()

        # Login to get token
        response = client.post("/api/v1/auth/login", json={
            "email": "admin@test.com",
            "password": "password123"
        })
        return response.json.get("access_token")


@pytest.fixture
def user_token(app, client):
    """Get JWT token for regular user (read-only)."""
    with app.app_context():
        read_perm = PermissionModel(
            id=uuid4(),
            name="project:read",
            resource="project",
            action="read"
        )
        db.session.add(read_perm)

        user_role = RoleModel(id=uuid4(), name="user", description="User")
        user_role.permissions = [read_perm]
        db.session.add(user_role)

        from app.infrastructure.adapters.argon2_password_hasher import Argon2PasswordHasher
        hasher = Argon2PasswordHasher()

        user = UserModel(
            id=uuid4(),
            email="user@test.com",
            password_hash=hasher.hash("password123"),
            is_active=True
        )
        user.roles = [user_role]
        db.session.add(user)
        db.session.commit()

        response = client.post("/api/v1/auth/login", json={
            "email": "user@test.com",
            "password": "password123"
        })
        return response.json.get("access_token")


class TestListProjects:
    """Test GET /api/v1/projects."""

    def test_list_projects_unauthorized(self, client):
        """Request without token returns 401."""
        response = client.get("/api/v1/projects")
        assert response.status_code == 401

    def test_list_projects_success(self, client, admin_token):
        """Admin can list projects."""
        response = client.get(
            "/api/v1/projects",
            headers={"Authorization": f"Bearer {admin_token}"}
        )
        assert response.status_code == 200
        assert "projects" in response.json


class TestCreateProject:
    """Test POST /api/v1/projects."""

    def test_create_project_success(self, client, admin_token):
        """Admin can create project."""
        response = client.post(
            "/api/v1/projects",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"name": "New Project", "address": "123 St"}
        )
        assert response.status_code == 201
        assert response.json["name"] == "New Project"

    def test_create_project_forbidden(self, client, user_token):
        """Regular user cannot create project."""
        response = client.post(
            "/api/v1/projects",
            headers={"Authorization": f"Bearer {user_token}"},
            json={"name": "New Project"}
        )
        assert response.status_code == 403

    def test_create_project_validation_error(self, client, admin_token):
        """Empty name returns 400."""
        response = client.post(
            "/api/v1/projects",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"name": ""}
        )
        assert response.status_code == 400


class TestGetProject:
    """Test GET /api/v1/projects/{id}."""

    def test_get_project_not_found(self, client, admin_token):
        """Non-existent project returns 404."""
        response = client.get(
            f"/api/v1/projects/{uuid4()}",
            headers={"Authorization": f"Bearer {admin_token}"}
        )
        assert response.status_code == 404


class TestUpdateProject:
    """Test PUT /api/v1/projects/{id}."""

    def test_update_project_forbidden(self, client, user_token):
        """Regular user cannot update project."""
        response = client.put(
            f"/api/v1/projects/{uuid4()}",
            headers={"Authorization": f"Bearer {user_token}"},
            json={"name": "Updated"}
        )
        assert response.status_code == 403


class TestDeleteProject:
    """Test DELETE /api/v1/projects/{id}."""

    def test_delete_project_forbidden(self, client, user_token):
        """Regular user cannot delete project."""
        response = client.delete(
            f"/api/v1/projects/{uuid4()}",
            headers={"Authorization": f"Bearer {user_token}"}
        )
        assert response.status_code == 403
```

### 5. Create Frontend Context Tests

File: `src/context/__tests__/ProjectContext.test.tsx`
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ProjectProvider, useProject } from '../ProjectContext';

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: vi.fn((key: string) => store[key] || null),
    setItem: vi.fn((key: string, value: string) => { store[key] = value; }),
    removeItem: vi.fn((key: string) => { delete store[key]; }),
    clear: vi.fn(() => { store = {}; }),
  };
})();
Object.defineProperty(window, 'localStorage', { value: localStorageMock });

// Mock fetch
const mockProjects = [
  { id: '1', name: 'Project A', address: '123 St', owner_id: 'owner1', user_count: 2, created_at: '2024-01-01' },
  { id: '2', name: 'Project B', address: null, owner_id: 'owner1', user_count: 0, created_at: '2024-01-02' },
];

global.fetch = vi.fn(() =>
  Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ projects: mockProjects, total: 2 }),
  } as Response)
);

// Test component to consume context
function TestConsumer() {
  const { projects, selectedProjectId, selectedProject, selectProject, isLoading, error } = useProject();
  return (
    <div>
      <span data-testid="loading">{isLoading ? 'loading' : 'loaded'}</span>
      <span data-testid="error">{error || 'no-error'}</span>
      <span data-testid="count">{projects.length}</span>
      <span data-testid="selected">{selectedProjectId || 'none'}</span>
      <span data-testid="selected-name">{selectedProject?.name || 'none'}</span>
      <button onClick={() => selectProject('2')}>Select Project B</button>
    </div>
  );
}

describe('ProjectContext', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorageMock.clear();
  });

  it('loads projects on mount', async () => {
    render(
      <ProjectProvider>
        <TestConsumer />
      </ProjectProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('loading')).toHaveTextContent('loaded');
    });

    expect(screen.getByTestId('count')).toHaveTextContent('2');
  });

  it('auto-selects first project when none stored', async () => {
    render(
      <ProjectProvider>
        <TestConsumer />
      </ProjectProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('selected')).toHaveTextContent('1');
    });
  });

  it('restores selection from localStorage', async () => {
    localStorageMock.getItem.mockReturnValue('2');

    render(
      <ProjectProvider>
        <TestConsumer />
      </ProjectProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('selected')).toHaveTextContent('2');
    });
  });

  it('persists selection to localStorage', async () => {
    const user = userEvent.setup();

    render(
      <ProjectProvider>
        <TestConsumer />
      </ProjectProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('loading')).toHaveTextContent('loaded');
    });

    await user.click(screen.getByText('Select Project B'));

    expect(localStorageMock.setItem).toHaveBeenCalledWith('selectedProjectId', '2');
  });

  it('handles fetch error gracefully', async () => {
    global.fetch = vi.fn(() => Promise.reject(new Error('Network error')));

    render(
      <ProjectProvider>
        <TestConsumer />
      </ProjectProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('error')).toHaveTextContent('Network error');
    });
  });

  it('throws error when useProject used outside provider', () => {
    expect(() => render(<TestConsumer />)).toThrow('useProject must be used within ProjectProvider');
  });
});
```

### 6. Create Frontend Component Tests

File: `src/components/project/__tests__/ProjectSelector.test.tsx`
```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ProjectSelector } from '../ProjectSelector';

// Mock the context
const mockSelectProject = vi.fn();
vi.mock('@/context/ProjectContext', () => ({
  useProject: vi.fn(() => ({
    projects: [
      { id: '1', name: 'Project A', address: '123 St' },
      { id: '2', name: 'Project B', address: null },
    ],
    selectedProjectId: '1',
    selectedProject: { id: '1', name: 'Project A' },
    selectProject: mockSelectProject,
    isLoading: false,
    error: null,
  })),
}));

describe('ProjectSelector', () => {
  it('renders dropdown with projects', () => {
    render(<ProjectSelector />);

    expect(screen.getByLabelText('Select project')).toBeInTheDocument();
    expect(screen.getByRole('combobox')).toHaveValue('1');
  });

  it('shows all project options', () => {
    render(<ProjectSelector />);

    const options = screen.getAllByRole('option');
    expect(options).toHaveLength(2);
    expect(options[0]).toHaveTextContent('Project A');
    expect(options[1]).toHaveTextContent('Project B');
  });

  it('calls selectProject on change', async () => {
    const user = userEvent.setup();
    render(<ProjectSelector />);

    await user.selectOptions(screen.getByRole('combobox'), '2');

    expect(mockSelectProject).toHaveBeenCalledWith('2');
  });
});

describe('ProjectSelector loading state', () => {
  it('shows loading indicator', () => {
    vi.mock('@/context/ProjectContext', () => ({
      useProject: () => ({
        projects: [],
        selectedProjectId: null,
        isLoading: true,
        error: null,
      }),
    }));

    render(<ProjectSelector />);

    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });
});

describe('ProjectSelector error state', () => {
  it('shows error message', () => {
    vi.mock('@/context/ProjectContext', () => ({
      useProject: () => ({
        projects: [],
        selectedProjectId: null,
        isLoading: false,
        error: 'Failed to load',
      }),
    }));

    render(<ProjectSelector />);

    expect(screen.getByText(/failed to load projects/i)).toBeInTheDocument();
  });
});

describe('ProjectSelector empty state', () => {
  it('shows empty message when no projects', () => {
    vi.mock('@/context/ProjectContext', () => ({
      useProject: () => ({
        projects: [],
        selectedProjectId: null,
        isLoading: false,
        error: null,
      }),
    }));

    render(<ProjectSelector />);

    expect(screen.getByText(/no projects available/i)).toBeInTheDocument();
  });
});
```

### 7. Create Frontend API Tests

File: `src/lib/api/__tests__/projects.test.ts`
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fetchProjects, fetchProjectById } from '../projects';

describe('fetchProjects', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns projects on success', async () => {
    const mockProjects = [
      { id: '1', name: 'Project A', address: '123', owner_id: 'o1', user_count: 1, created_at: '2024-01-01' },
    ];

    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ projects: mockProjects, total: 1 }),
      } as Response)
    );

    const result = await fetchProjects();

    expect(result).toEqual(mockProjects);
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/v1/projects'),
      expect.objectContaining({ credentials: 'include' })
    );
  });

  it('throws error on failure', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: false,
        status: 401,
      } as Response)
    );

    await expect(fetchProjects()).rejects.toThrow('Failed to fetch projects: 401');
  });
});

describe('fetchProjectById', () => {
  it('returns project on success', async () => {
    const mockProject = { id: '1', name: 'Project A' };

    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve(mockProject),
      } as Response)
    );

    const result = await fetchProjectById('1');

    expect(result).toEqual(mockProject);
  });

  it('throws error on 404', async () => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: false,
        status: 404,
      } as Response)
    );

    await expect(fetchProjectById('nonexistent')).rejects.toThrow('Failed to fetch project: 404');
  });
});
```

## Todo List

- [ ] Add project fixtures to `conftest.py`
- [ ] Create `test_project_repository.py`
- [ ] Create `test_project_usecases.py`
- [ ] Create `test_project_endpoints.py`
- [ ] Run backend tests: `pytest tests/test_project*.py -v`
- [ ] Create frontend test directories
- [ ] Create `ProjectContext.test.tsx`
- [ ] Create `ProjectSelector.test.tsx`
- [ ] Create `projects.test.ts`
- [ ] Run frontend tests: `npm run test`
- [ ] Verify all tests pass
- [ ] Check test coverage

## Success Criteria

1. Backend tests pass: repository, use cases, endpoints
2. Frontend tests pass: context, components, API
3. RBAC tested: admin access granted, user access denied (403)
4. Error states tested: 401, 403, 404, validation errors
5. LocalStorage persistence tested

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Flaky auth tests | Medium | Use consistent test fixtures |
| Mock drift | Medium | Keep mocks close to real impl |
| Missing edge cases | Low | Add tests as bugs found |

## Security Considerations

- Test permission checks explicitly
- Verify 403 for unauthorized write ops
- Test invalid JWT handling (401)
- No real credentials in tests

## Next Steps

After completion:
1. Run full test suite before merge
2. Add tests to CI/CD pipeline
3. Document test coverage requirements
