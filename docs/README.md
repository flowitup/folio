# Construction Management System

A full-stack construction management platform with hexagonal architecture, built with Flask (Python) backend and Next.js (React) frontend.

## Overview

The Construction Management System (CMS) enables teams to manage construction projects efficiently with features for authentication, role-based access control (RBAC), project management, and team collaboration.

**Status:** ✅ **Production live** at https://folio.flowitup.com (deployed 2026-05-03)
**Deploy:** Single GCE e2-standard-2 VM in europe-west1, Cloudflare Tunnel, GCS-backed backups
**Runbook:** [`docs/deployment-guide.md`](./deployment-guide.md)

## Tech Stack

### Backend
- **Framework:** Flask 3.0 + SQLAlchemy 2.0
- **Language:** Python 3.12
- **Database:** PostgreSQL with Alembic migrations
- **Cache/Session:** Redis
- **Authentication:** JWT + HTTP-only cookies, Argon2 hashing
- **API Design:** REST v1, Pydantic validation, Flask-RESTX Swagger
- **Architecture:** Hexagonal (Ports & Adapters) + DDD

### Frontend
- **Framework:** Next.js 16 with App Router
- **Library:** React 19 + TypeScript 5
- **Styling:** Tailwind CSS v4 + shadcn/ui (Radix UI primitives)
- **i18n:** next-intl (en, vi, fr support)
- **Testing:** Vitest + React Testing Library
- **Design:** Fintech-minimalist aesthetic

### App-level
- **Auth:** Flask-JWT-Extended, Argon2-cffi
- **Rate Limiting:** Flask-Limiter (Redis-backed)
- **Task Queue:** RQ (future: Celery)
- **Email:** Resend (transactional, free tier)

### Production infrastructure
- **Cloud:** GCP (project `flowitup-folio-prod`, org `mtbui-creative-org`, region `europe-west1`)
- **Compute:** Single GCE `e2-standard-2` VM running 6 Docker containers (Flask api, RQ worker, Postgres 16, Redis 7, MinIO, Next.js)
- **Edge:** Cloudflare DNS + WAF + Tunnel (no public IP on VM, IAP-only SSH)
- **Registry:** Artifact Registry — `europe-west1-docker.pkg.dev/flowitup-folio-prod/folio/{api,frontend}`
- **Secrets:** Google Secret Manager (20 keys, rendered to `/opt/folio/.env` via systemd oneshot)
- **Backups:** Daily `pg_dump` + MinIO mirror → `gs://flowitup-folio-prod-backups`; weekly disk snapshots
- **Monitoring:** Cloud Logging + Cloud Monitoring (uptime check + disk-usage alert), email channel

## Quick Start

### Prerequisites
- Docker & Docker Compose
- Node.js 20+ (for frontend development)
- Python 3.12+ (for backend development)
- PostgreSQL 15+ (if running outside Docker)
- Redis 7+ (if running outside Docker)

### Local Development

**1. Setup Environment**
```bash
# Clone and navigate to project root
cd /path/to/construction

# Backend setup
cd construction-back-end
cp .env.example .env
pip install -r requirements.txt
flask db upgrade
python run.py

# Frontend setup (in another terminal)
cd construction-front-end
npm install
npm run dev
```

**2. Access Application**
- Frontend: http://localhost:3000
- Backend API: http://localhost:5000/api/v1
- API Documentation: http://localhost:5000/api/v1/swagger

**3. Default Credentials** (seeded automatically)
- Email: `admin@example.com`
- Password: `password123`

### Docker Deployment

```bash
# Start all services
docker-compose up -d

# Verify services
./scripts/verify-setup.sh
```

**Verify Output:**
- Database migrations run automatically
- Admin user seeded
- Frontend dev server accessible at http://localhost:3000
- Backend API responding at http://localhost:5000/api/v1

## Project Structure

```
construction/
├── construction-back-end/          # Flask REST API
│   ├── app/
│   │   ├── api/v1/                # Endpoints (adapters)
│   │   ├── application/           # Use cases
│   │   ├── domain/                # Business logic
│   │   └── infrastructure/        # External services
│   ├── migrations/                # Alembic database versions
│   ├── tests/                     # Integration & unit tests
│   └── config/                    # Environment configuration
│
├── construction-front-end/        # Next.js React frontend
│   ├── src/
│   │   ├── app/                  # App Router pages & layouts
│   │   ├── components/           # React components
│   │   ├── lib/                  # Utilities & hooks
│   │   ├── context/              # React context state
│   │   └── __tests__/            # Vitest tests
│   ├── messages/                 # i18n translations
│   └── public/                   # Static assets
│
├── docs/                          # Project documentation
│   ├── README.md                 # This file
│   ├── project-overview-pdr.md   # Goals & requirements
│   ├── system-architecture.md    # Architecture details
│   ├── code-standards.md         # Coding standards
│   ├── codebase-summary.md       # Implementation status
│   └── ...
│
└── scripts/                       # Utility scripts
    └── verify-setup.sh           # E2E setup verification
```

## Key Features

### Authentication & Authorization
- Secure login with email/password (Argon2 hashing)
- JWT tokens (30min access, 7day refresh)
- Role-based access control (admin, manager, user)
- Token revocation via Redis blacklist
- Rate limiting (5 login attempts/minute)

### API Layer
- REST v1 endpoints with Pydantic validation
- Request/response standardization
- JWT middleware for protected routes
- Comprehensive error handling
- Swagger documentation

### Frontend Features
- Server-side authentication with cookies
- Protected routes with middleware
- Responsive UI with Tailwind + shadcn components
- Multi-language support (English, Vietnamese, French)
- Dark mode support (system preference)

## Development Workflow

### Code Standards
- **Backend:** Python PEP 8, mypy type checking, Ruff linting
- **Frontend:** ESLint, TypeScript strict, Prettier formatting
- Read detailed standards in [Code Standards](./docs/code-standards.md)

### Testing
**Backend:**
```bash
pytest tests/
pytest --cov=app tests/  # With coverage
```

**Frontend:**
```bash
npm run test              # Single run
npm run test:watch       # Watch mode
npm run type-check       # TypeScript validation
```

### Building & Deployment
```bash
# Backend
python run.py             # Development
gunicorn app:app          # Production

# Frontend
npm run build            # Production bundle
npm run dev              # Development server
```

## API Documentation

### Base URL
```
http://localhost:5000/api/v1
```

### Authentication Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/auth/login` | None | Login with email/password |
| POST | `/auth/logout` | Optional | Logout, revoke token |
| POST | `/auth/refresh` | Refresh | Get new access token |
| GET | `/auth/me` | Required | Current user info |

### Example: Login
```bash
curl -X POST http://localhost:5000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "password123"
  }'
```

**Response (200):**
```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "refresh_token": "eyJ0eXAiOiJKV1QiLCJhbGc...",
  "token_type": "Bearer",
  "expires_in": 1800,
  "user": {
    "id": "uuid",
    "email": "admin@example.com",
    "roles": ["admin"],
    "permissions": ["*:*"]
  }
}
```

See [system-architecture.md](./docs/system-architecture.md) for detailed API design & flows.

## Documentation

Essential docs in `./docs/`:

- **[System Architecture](./docs/system-architecture.md)** - High-level architecture, component interactions, data flows
- **[Code Standards](./docs/code-standards.md)** - Coding conventions, project structure, naming rules
- **[Codebase Summary](./docs/codebase-summary.md)** - Implementation status, recent changes, tech stack
- **[Project Overview & PDR](./docs/project-overview-pdr.md)** - Goals, scope, requirements, success criteria
- **[Security Checklist](./docs/security-checklist.md)** - OWASP coverage, security features, deployment checklist

## Contributing

1. Read [Code Standards](./docs/code-standards.md)
2. Create feature branch: `git checkout -b feat/feature-name`
3. Commit with conventional messages: `feat(scope): description`
4. Push & create pull request
5. Ensure tests pass & code review approved

## Deployment

### Development
- Local: `docker-compose up -d` + `npm run dev`
- Verification: `./scripts/verify-setup.sh`

### Production (Future)
- Backend: AWS ECS / Google Cloud Run
- Frontend: Vercel / Netlify
- Database: AWS RDS PostgreSQL
- Cache: AWS ElastiCache Redis

See [deployment-guide.md](./docs/deployment-guide.md) (future) for details.

## Roadmap

**Phase 04:** Frontend auth infrastructure (COMPLETED)
**Phase 05:** Frontend login UI
**Phase 06:** Project management features
**Phase 07:** Team collaboration & permissions
**Phase 08:** Advanced analytics & reporting

See [project-roadmap.md](./docs/project-roadmap.md) for full roadmap.

## Troubleshooting

**Port already in use:**
```bash
# Backend (5000)
lsof -i :5000 | grep -v PID | awk '{print $2}' | xargs kill -9

# Frontend (3000)
lsof -i :3000 | grep -v PID | awk '{print $2}' | xargs kill -9
```

**Database connection error:**
```bash
# Verify PostgreSQL running
psql $DATABASE_URL -c "SELECT 1"

# Reset migrations
flask db downgrade base
flask db upgrade
```

**Redis connection error:**
```bash
# Verify Redis running
redis-cli ping  # Should return PONG
```

For more help, see [System Architecture - Troubleshooting](./docs/system-architecture.md).

## License

Proprietary - Construction Management System
All rights reserved.

## Contact

For questions or issues, see [CONTRIBUTING.md](./docs/CONTRIBUTING.md) (future).
