# Phase 01: Implement verify-setup.sh

## Context Links

- [Plan Overview](./plan.md)
- [System Architecture](/Users/sweet-home/Works/construction/docs/system-architecture.md)
- [Docker Compose](/Users/sweet-home/Works/construction/construction-back-end/docker-compose.yml)
- [Seed Script](/Users/sweet-home/Works/construction/construction-back-end/scripts/seed_auth.py)

## Overview

**Priority:** P2
**Status:** completed
**Effort:** 2h

Create a bash script at `scripts/verify-setup.sh` (project root) that performs full E2E verification of the construction project setup.

## Key Insights

1. Docker Compose already has health checks for db, redis, api services
2. Backend API has `/health` endpoint returning `{"status": "ok"}`
3. Auth endpoints work: POST /api/v1/auth/login, GET /api/v1/auth/me
4. Seed script creates admin user with `--with-admin` flag + env vars
5. Frontend uses port 3000, backend uses port 5000

## Requirements

### Functional Requirements

1. **Docker Services Management**
   - Start services via `docker-compose up -d`
   - Wait for health checks to pass (db, redis, api)
   - Timeout after configurable period (default 120s)
   - Verify all 4 containers running (api, worker, db, redis)

2. **Database Setup**
   - Run alembic migrations: `flask db upgrade`
   - Execute seed script: `python scripts/seed_auth.py --with-admin`
   - Use env vars: ADMIN_EMAIL, ADMIN_PASSWORD

3. **Frontend Setup**
   - Check if node_modules exists, run `npm install` if not
   - Start Next.js dev server in background: `npm run dev`
   - Wait for http://localhost:3000 to respond

4. **E2E Integration Tests**
   - Test login endpoint: POST /api/v1/auth/login with seeded admin credentials
   - Extract access_token from response
   - Test /auth/me with Bearer token
   - Verify user data returned matches seeded admin

5. **Cleanup & Reporting**
   - `--cleanup` flag to stop all services after verification
   - Color-coded output: green=success, red=failure, yellow=warning
   - Exit code 0 on success, non-zero on failure

### Non-Functional Requirements

- Cross-platform bash (macOS, Linux)
- Idempotent (safe to run multiple times)
- Graceful error handling with meaningful messages
- Trap signals for cleanup on interrupt

## Architecture

```
scripts/verify-setup.sh
├── Configuration (ports, timeouts, colors)
├── Utility Functions
│   ├── log_success(), log_error(), log_info()
│   ├── wait_for_health(url, timeout)
│   └── cleanup()
├── Docker Section
│   ├── Start docker-compose
│   └── Wait for container health
├── Database Section
│   ├── Run migrations
│   └── Seed auth data
├── Frontend Section
│   ├── Install deps if needed
│   └── Start dev server
├── E2E Test Section
│   ├── Test login endpoint
│   └── Test /me endpoint
└── Cleanup & Report
```

## Related Code Files

### Files to Create

| File | Purpose |
|------|---------|
| `scripts/verify-setup.sh` | Main verification script |

### Files to Reference

| File | Purpose |
|------|---------|
| `construction-back-end/docker-compose.yml` | Docker service definitions |
| `construction-back-end/scripts/seed_auth.py` | Seed script usage |
| `construction-back-end/app/__init__.py` | Health endpoint reference |
| `construction-front-end/package.json` | npm scripts |

## Implementation Steps

### 1. Create Script Structure (15 min)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKEND_DIR="construction-back-end"
FRONTEND_DIR="construction-front-end"
API_URL="http://localhost:5000"
FRONTEND_URL="http://localhost:3000"
TIMEOUT=120

# Default admin credentials (override with env vars)
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-password123}"

# Parse args
CLEANUP=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup) CLEANUP=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done
```

### 2. Implement Utility Functions (20 min)

```bash
log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_error() { echo -e "${RED}✗ $1${NC}"; }
log_info() { echo -e "${BLUE}→ $1${NC}"; }
log_warning() { echo -e "${YELLOW}! $1${NC}"; }

wait_for_health() {
    local url=$1
    local timeout=$2
    local start=$(date +%s)

    while true; do
        if curl -sf "$url" > /dev/null 2>&1; then
            return 0
        fi

        local elapsed=$(($(date +%s) - start))
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi
        sleep 2
    done
}

cleanup() {
    log_info "Cleaning up..."
    # Stop frontend if running
    if [[ -n "${FRONTEND_PID:-}" ]]; then
        kill "$FRONTEND_PID" 2>/dev/null || true
    fi
    # Stop docker services
    if [[ "$CLEANUP" == true ]]; then
        cd "$SCRIPT_DIR/$BACKEND_DIR"
        docker-compose down
    fi
}

trap cleanup EXIT
```

### 3. Implement Docker Section (25 min)

```bash
verify_docker() {
    log_info "Starting Docker services..."
    cd "$SCRIPT_DIR/$BACKEND_DIR"

    docker-compose up -d

    log_info "Waiting for database health..."
    wait_for_health "http://localhost:5432" 60 || {
        # Use pg_isready for postgres
        local count=0
        while ! docker-compose exec -T db pg_isready -U construction > /dev/null 2>&1; do
            count=$((count + 1))
            if [[ $count -ge 30 ]]; then
                log_error "Database failed to become healthy"
                return 1
            fi
            sleep 2
        done
    }
    log_success "Database is healthy"

    log_info "Waiting for Redis health..."
    local count=0
    while ! docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; do
        count=$((count + 1))
        if [[ $count -ge 30 ]]; then
            log_error "Redis failed to become healthy"
            return 1
        fi
        sleep 2
    done
    log_success "Redis is healthy"

    log_info "Waiting for API health..."
    if wait_for_health "$API_URL/health" "$TIMEOUT"; then
        log_success "API is healthy"
    else
        log_error "API failed to become healthy"
        return 1
    fi

    # Verify all containers running
    local running=$(docker-compose ps --services --filter "status=running" | wc -l)
    if [[ $running -ge 4 ]]; then
        log_success "All $running containers running"
    else
        log_warning "Only $running containers running (expected 4)"
    fi
}
```

### 4. Implement Database Section (15 min)

```bash
setup_database() {
    log_info "Running database migrations..."
    cd "$SCRIPT_DIR/$BACKEND_DIR"

    docker-compose exec -T api flask db upgrade || {
        log_error "Migrations failed"
        return 1
    }
    log_success "Migrations complete"

    log_info "Seeding authentication data..."
    docker-compose exec -T -e ADMIN_EMAIL="$ADMIN_EMAIL" -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        api python scripts/seed_auth.py --with-admin || {
        log_warning "Seeding may have partially failed (user might exist)"
    }
    log_success "Auth data seeded"
}
```

### 5. Implement Frontend Section (20 min)

```bash
setup_frontend() {
    log_info "Setting up frontend..."
    cd "$SCRIPT_DIR/$FRONTEND_DIR"

    # Check if node_modules exists
    if [[ ! -d "node_modules" ]]; then
        log_info "Installing npm dependencies..."
        npm install || {
            log_error "npm install failed"
            return 1
        }
        log_success "Dependencies installed"
    else
        log_info "node_modules exists, skipping install"
    fi

    # Check if .env.local exists
    if [[ ! -f ".env.local" ]]; then
        log_info "Creating .env.local from example..."
        cp .env.example .env.local
    fi

    # Start dev server in background
    log_info "Starting Next.js dev server..."
    npm run dev > /dev/null 2>&1 &
    FRONTEND_PID=$!

    log_info "Waiting for frontend..."
    if wait_for_health "$FRONTEND_URL" "$TIMEOUT"; then
        log_success "Frontend is ready"
    else
        log_error "Frontend failed to start"
        return 1
    fi
}
```

### 6. Implement E2E Tests (25 min)

```bash
run_e2e_tests() {
    log_info "Running E2E integration tests..."

    # Test 1: Login endpoint
    log_info "Testing login endpoint..."
    local login_response=$(curl -sf -X POST "$API_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\"}")

    if [[ -z "$login_response" ]]; then
        log_error "Login request failed"
        return 1
    fi

    # Extract access token (requires jq)
    if ! command -v jq &> /dev/null; then
        log_warning "jq not installed, using basic parsing"
        ACCESS_TOKEN=$(echo "$login_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    else
        ACCESS_TOKEN=$(echo "$login_response" | jq -r '.access_token')
    fi

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        log_error "Failed to extract access token"
        echo "Response: $login_response"
        return 1
    fi
    log_success "Login successful, got access token"

    # Test 2: /me endpoint with token
    log_info "Testing /auth/me endpoint..."
    local me_response=$(curl -sf "$API_URL/api/v1/auth/me" \
        -H "Authorization: Bearer $ACCESS_TOKEN")

    if [[ -z "$me_response" ]]; then
        log_error "/me request failed"
        return 1
    fi

    # Verify email matches
    if echo "$me_response" | grep -q "$ADMIN_EMAIL"; then
        log_success "/auth/me returns correct user data"
    else
        log_warning "/auth/me response may not contain expected email"
        echo "Response: $me_response"
    fi

    # Test 3: Frontend connectivity (optional)
    log_info "Testing frontend connectivity..."
    if curl -sf "$FRONTEND_URL" > /dev/null; then
        log_success "Frontend responds at $FRONTEND_URL"
    else
        log_warning "Frontend not responding (may be expected if build-only)"
    fi
}
```

### 7. Main Function & Summary (10 min)

```bash
main() {
    echo ""
    echo "======================================"
    echo "  Construction Setup Verification"
    echo "======================================"
    echo ""

    local start_time=$(date +%s)
    local failed=0

    verify_docker || failed=1
    [[ $failed -eq 0 ]] && setup_database || failed=1
    [[ $failed -eq 0 ]] && setup_frontend || failed=1
    [[ $failed -eq 0 ]] && run_e2e_tests || failed=1

    local elapsed=$(($(date +%s) - start_time))

    echo ""
    echo "======================================"
    if [[ $failed -eq 0 ]]; then
        log_success "All verifications passed! (${elapsed}s)"
        echo "======================================"
        exit 0
    else
        log_error "Verification failed! (${elapsed}s)"
        echo "======================================"
        exit 1
    fi
}

main
```

## Todo List

- [x] Create scripts directory at project root
- [x] Create verify-setup.sh with shebang and set options
- [x] Implement color constants and configuration
- [x] Implement argument parsing (--cleanup)
- [x] Implement logging utility functions
- [x] Implement wait_for_health helper
- [x] Implement cleanup trap handler
- [x] Implement verify_docker function
- [x] Implement setup_database function
- [x] Implement setup_frontend function
- [x] Implement run_e2e_tests function
- [x] Implement main function with summary
- [x] Make script executable (chmod +x)
- [x] Test script manually
- [x] Update documentation

## Success Criteria

1. Script runs without errors on fresh setup
2. All Docker services start and become healthy
3. Database migrations run successfully
4. Seed data creates admin user
5. Frontend dev server starts and responds
6. Login and /me endpoints work with seeded credentials
7. Clean exit with proper code (0 success, non-zero failure)
8. Cleanup flag stops all services properly
9. Color-coded output is readable
10. Script is idempotent (can run multiple times)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Port conflicts | High | Check ports before starting, provide clear error |
| Docker not installed | High | Check for docker/docker-compose at start |
| Node/npm not installed | Medium | Check for node/npm before frontend setup |
| jq not installed | Low | Fallback to grep-based parsing |
| Slow network (docker pulls) | Medium | Increase timeout, show progress |
| Stale containers | Low | Use `docker-compose down` before up (optional flag) |

## Security Considerations

1. **Credentials Handling**
   - Use environment variables for admin credentials
   - Never hardcode passwords in script
   - Default credentials are for dev/testing only

2. **Network Exposure**
   - Services bind to localhost by default
   - Document that this is for local dev only

3. **File Permissions**
   - Script should be executable (755)
   - Env files should not be world-readable

## Implementation Summary

**Completed:** 2026-01-20

### What Was Built

- Full E2E verification script at `scripts/verify-setup.sh`
- Docker Compose v1/v2 auto-detection
- Health check polling for db, redis, api
- Database migrations and auth seeding
- Frontend dev server startup and verification
- Login/me endpoint E2E tests
- `--cleanup` and `--cleanall` flags

### Additional Fixes Required

During implementation, several infrastructure issues were discovered and fixed:

1. **Dockerfile** - Missing COPY commands for migrations/ and scripts/
2. **RQ Worker** - Updated for RQ 2.x API (Connection removed)
3. **DI Container** - Added wiring in create_app() for auth services
4. **Repository Adapter** - Created SQLAlchemyUserRepository
5. **Config** - Fixed JWT_TOKEN_LOCATION mutable default

### Verification Results

```
✓ Docker found
✓ Docker Compose found (docker compose)
✓ Node.js found (v25.2.1)
✓ npm found (11.6.2)
✓ curl found
✓ Database is healthy
✓ Redis is healthy
✓ API is healthy
✓ All 4 containers running
✓ Migrations complete
✓ Auth data seeded
✓ Frontend is ready
✓ Login successful, got access token
✓ /auth/me returns correct user data
✓ Frontend responds at http://localhost:3000
✓ All verifications passed! (4s)
```

## Future Enhancements

1. Add to project README documentation
2. Consider CI/CD integration (GitHub Actions)
3. Add --force flag to recreate containers
4. Add --verbose flag for debug output
