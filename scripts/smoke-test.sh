#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Construction Project Setup Verification Script
# Performs full E2E verification: Docker, DB, Frontend, Auth flow
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKEND_DIR="construction-back-end"
FRONTEND_DIR="construction-front-end"
API_URL="http://localhost:5000"
FRONTEND_URL="http://localhost:3000"
TIMEOUT=120

# Default admin credentials (override with env vars)
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-password123}"

# State
CLEANUP=false
CLEAN_ALL=false
QUICK_REBUILD=""
FRONTEND_PID=""
DOCKER_COMPOSE=""
TARGET_CONTEXT="default"
REMOTE_HOST=""

# =============================================================================
# Argument Parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup)  CLEANUP=true; shift ;;
        --cleanall) CLEAN_ALL=true; shift ;;
        --quick)    QUICK_REBUILD="$2"; shift 2 ;;
        --context)  TARGET_CONTEXT="$2"; shift 2 ;;
        --host)     REMOTE_HOST="$2"; shift 2 ;;
        --timeout)
            if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --timeout requires a positive integer"
                exit 1
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --cleanup      Stop all services after verification
  --cleanall     Remove all Docker containers, volumes, caches, and storage
  --quick SVC    Quick rebuild: restart only specified service (api|frontend|all)
                 Skips prerequisites check, migrations, and seeding
  --context NAME Docker context to use (default: default)
  --host IP      Remote host IP (required with --context)
  --timeout N    Set timeout in seconds (default: 120)
  --help, -h     Show this help message

Quick rebuild examples:
  $0 --quick api        # Rebuild and restart only the API service
  $0 --quick frontend   # Restart only the frontend
  $0 --quick all        # Rebuild all services without full setup

Environment variables:
  ADMIN_EMAIL     Admin email for seeding (default: admin@example.com)
  ADMIN_PASSWORD  Admin password for seeding (default: password123)
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1"; echo "Use --help for usage information"; exit 1 ;;
    esac
done

# =============================================================================
# Utility Functions
# =============================================================================
log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_error()   { echo -e "${RED}✗ $1${NC}"; }
log_info()    { echo -e "${BLUE}→ $1${NC}"; }
log_warning() { echo -e "${YELLOW}! $1${NC}"; }

# Validate and cd into a project subdirectory
# Usage: enter_dir "$BACKEND_DIR" || return 1
enter_dir() {
    local dir="$SCRIPT_DIR/$1"
    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi
    cd "$dir"
}

# Perform an HTTP request, setting global HTTP_BODY and HTTP_CODE
# Usage: http_request METHOD URL [extra_curl_args...]
HTTP_BODY=""
HTTP_CODE=""
http_request() {
    local method="$1" url="$2"
    shift 2
    local raw
    raw=$(curl -s -o /dev/fd/1 -w "\n%{http_code}" --connect-timeout 10 \
        -X "$method" "$@" "$url" 2>&1)
    HTTP_CODE=$(echo "$raw" | tail -1)
    HTTP_BODY=$(echo "$raw" | sed '$d')
}

# Assert last http_request returned 2xx with a non-empty body
# Usage: assert_http_ok "endpoint name" "$url" || return 1
assert_http_ok() {
    local name="$1" url="$2"
    if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
        log_error "$name failed (HTTP $HTTP_CODE): $url"
        echo "Response: $HTTP_BODY"
        return 1
    fi
    if [[ -z "$HTTP_BODY" ]]; then
        log_error "Empty $name response (HTTP $HTTP_CODE)"
        return 1
    fi
}

# Poll a command until it succeeds (every 2s, up to N iterations)
# Usage: wait_for_cmd 30 "Database" cmd arg1 arg2 ...
wait_for_cmd() {
    local max_attempts="$1" desc="$2"
    shift 2
    local count=0
    while ! "$@" > /dev/null 2>&1; do
        count=$((count + 1))
        if [[ $count -ge $max_attempts ]]; then
            log_error "$desc failed to become healthy"
            return 1
        fi
        sleep 2
    done
    log_success "$desc is healthy"
}

# Wait for an HTTP endpoint to return 2xx/3xx within a timeout
wait_for_health() {
    local url="$1" timeout="$2"
    local start
    start=$(date +%s)
    log_info "Health check: $url (timeout: ${timeout}s)"

    while true; do
        http_request GET "$url"
        [[ "$HTTP_CODE" =~ ^[23] ]] && return 0

        local elapsed=$(($(date +%s) - start))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timed out waiting for $url (last HTTP $HTTP_CODE):"
            echo "$HTTP_BODY" | head -20
            return 1
        fi
        sleep 2
    done
}

# Extract a JSON field (uses jq if available, grep fallback)
json_extract() {
    local json="$1" field="$2"
    if command -v jq &> /dev/null; then
        echo "$json" | jq -r ".$field // empty"
    else
        echo "$json" | grep -oE "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
            | grep -oE '"[^"]*"$' | tr -d '"'
    fi
}

# =============================================================================
# Docker Context
# =============================================================================
switch_docker_context() {
    local target="${1:-default}"
    local current
    current=$(docker context show 2>/dev/null || echo "")

    if [[ "$current" != "$target" ]]; then
        log_info "Switching docker context: '$current' → '$target'..."
        if ! docker context use "$target" > /dev/null 2>&1; then
            log_error "Failed to switch docker context to '$target'"
            return 1
        fi
        log_success "Docker context switched to '$target'"
    else
        log_info "Already using docker context '$target'"
    fi

    if [[ "$target" != "default" ]]; then
        if [[ -z "$REMOTE_HOST" ]]; then
            log_error "--host IP is required when using --context"
            return 1
        fi
        API_URL="http://${REMOTE_HOST}:5000"
        FRONTEND_URL="http://${REMOTE_HOST}:3000"
        log_info "API URL: $API_URL | Frontend URL: $FRONTEND_URL"
    fi
}

detect_docker_compose() {
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        return 1
    fi
}

# =============================================================================
# Cleanup
# =============================================================================
cleanup() {
    log_info "Cleaning up..."
    if [[ -n "${FRONTEND_PID:-}" ]]; then
        kill "$FRONTEND_PID" 2>/dev/null || true
        wait "$FRONTEND_PID" 2>/dev/null || true
    fi
    if [[ "$CLEANUP" == true ]] && [[ -n "$DOCKER_COMPOSE" ]]; then
        (enter_dir "$BACKEND_DIR" && $DOCKER_COMPOSE down 2>/dev/null) || true
        if [[ "$TARGET_CONTEXT" != "default" ]] && [[ -d "$SCRIPT_DIR/$FRONTEND_DIR" ]]; then
            (enter_dir "$FRONTEND_DIR" && $DOCKER_COMPOSE down 2>/dev/null) || true
        fi
        log_success "Docker services stopped"
    fi
}
trap cleanup EXIT

clean_all_docker() {
    log_info "Performing full Docker cleanup..."
    enter_dir "$BACKEND_DIR" || return 1

    $DOCKER_COMPOSE down --remove-orphans 2>/dev/null || true
    $DOCKER_COMPOSE down -v 2>/dev/null || true

    log_info "Removing project images and pruning cache..."
    docker images --filter "reference=construction-back-end*" -q | xargs -r docker rmi -f 2>/dev/null || true
    docker builder prune -f 2>/dev/null || true
    docker image prune -f 2>/dev/null || true
    docker volume prune -f 2>/dev/null || true

    log_success "Full Docker cleanup complete"
}

# =============================================================================
# Quick Rebuild (Development Mode)
# =============================================================================
quick_rebuild() {
    local service="$1"
    log_info "Quick rebuild mode: $service"

    detect_docker_compose || { log_error "Docker Compose not found"; return 1; }

    case "$service" in
        api)
            log_info "Rebuilding API service (no cache)..."
            enter_dir "$BACKEND_DIR" || return 1
            $DOCKER_COMPOSE build --no-cache api || return 1
            $DOCKER_COMPOSE up -d --force-recreate --no-deps api || return 1
            wait_for_health "$API_URL/health" "$TIMEOUT" || return 1
            log_success "API rebuilt and healthy"
            ;;
        frontend)
            log_info "Restarting frontend..."
            if [[ "$TARGET_CONTEXT" != "default" ]]; then
                enter_dir "$FRONTEND_DIR" || return 1
                $DOCKER_COMPOSE build --no-cache frontend || return 1
                $DOCKER_COMPOSE up -d --force-recreate --no-deps frontend || return 1
                wait_for_health "$FRONTEND_URL" "$TIMEOUT" || return 1
            else
                # Kill existing frontend process if running
                pkill -f "next dev" 2>/dev/null || true
                sleep 1
                setup_frontend_local || return 1
            fi
            log_success "Frontend restarted"
            ;;
        all)
            log_info "Rebuilding all services (no cache)..."
            enter_dir "$BACKEND_DIR" || return 1
            $DOCKER_COMPOSE build --no-cache || return 1
            $DOCKER_COMPOSE up -d --force-recreate || return 1
            wait_for_health "$API_URL/health" "$TIMEOUT" || return 1
            log_success "Backend services rebuilt"

            if [[ "$TARGET_CONTEXT" != "default" ]]; then
                enter_dir "$FRONTEND_DIR" || return 1
                $DOCKER_COMPOSE build --no-cache || return 1
                $DOCKER_COMPOSE up -d --force-recreate || return 1
                wait_for_health "$FRONTEND_URL" "$TIMEOUT" || return 1
            else
                pkill -f "next dev" 2>/dev/null || true
                sleep 1
                setup_frontend_local || return 1
            fi
            log_success "All services rebuilt"
            ;;
        *)
            log_error "Unknown service: $service (use: api, frontend, all)"
            return 1
            ;;
    esac

    log_success "Quick rebuild complete!"
}

# =============================================================================
# Prerequisites
# =============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    local missing=0

    for cmd in docker node npm curl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed"
            missing=1
        else
            local info="$cmd"
            case $cmd in
                node) info="Node.js ($(node --version))" ;;
                npm)  info="npm ($(npm --version))" ;;
            esac
            log_success "$info found"
        fi
    done

    if detect_docker_compose; then
        log_success "Docker Compose found ($DOCKER_COMPOSE)"
    else
        log_error "Docker Compose is not installed"
        missing=1
    fi

    [[ $missing -eq 0 ]] || { log_error "Missing prerequisites"; return 1; }
}

# =============================================================================
# Docker Services
# =============================================================================
verify_docker() {
    log_info "Starting Docker services..."
    enter_dir "$BACKEND_DIR" || return 1

    $DOCKER_COMPOSE up -d || {
        log_error "Failed to start Docker services. Is the Docker daemon running?"
        return 1
    }

    wait_for_cmd 30 "Database" $DOCKER_COMPOSE exec -T db pg_isready -U construction || return 1
    wait_for_cmd 30 "Redis" $DOCKER_COMPOSE exec -T redis redis-cli ping || return 1

    if wait_for_health "$API_URL/health" "$TIMEOUT"; then
        log_success "API is healthy"
    else
        log_error "API failed to become healthy within ${TIMEOUT}s"
        $DOCKER_COMPOSE logs --tail=30 api 2>/dev/null || true
        return 1
    fi

    local running
    running=$($DOCKER_COMPOSE ps --services --filter "status=running" 2>/dev/null | wc -l | tr -d ' ')
    if [[ $running -ge 4 ]]; then
        log_success "All $running containers running"
    else
        log_warning "Only $running containers running (expected 4)"
    fi
}

# =============================================================================
# Database Setup
# =============================================================================
setup_database() {
    log_info "Running database migrations..."
    enter_dir "$BACKEND_DIR" || return 1

    $DOCKER_COMPOSE exec -T api flask db upgrade || { log_error "Migrations failed"; return 1; }
    log_success "Migrations complete"

    log_info "Seeding auth data and projects..."
    $DOCKER_COMPOSE exec -T \
        -e ADMIN_EMAIL="$ADMIN_EMAIL" \
        -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        -e PYTHONPATH=/app \
        api python scripts/seed.py --with-admin --with-projects || {
        log_warning "Seeding may have partially failed (data might exist)"
    }
    log_success "Auth data and projects seeded"
}

# =============================================================================
# Frontend Setup
# =============================================================================
setup_frontend() {
    log_info "Setting up frontend..."
    if [[ "$TARGET_CONTEXT" != "default" ]]; then
        setup_frontend_remote; return
    fi
    setup_frontend_local
}

setup_frontend_remote() {
    log_info "Remote context: starting frontend Docker container..."
    enter_dir "$FRONTEND_DIR" || return 1

    NEXT_PUBLIC_API_BASE_URL="http://${REMOTE_HOST}:5000/api/v1" \
        $DOCKER_COMPOSE up -d --build || {
        log_error "Failed to start frontend Docker service"
        return 1
    }

    if wait_for_health "$FRONTEND_URL" "$TIMEOUT"; then
        log_success "Frontend is ready at $FRONTEND_URL"
    else
        log_error "Frontend not reachable within ${TIMEOUT}s"
        $DOCKER_COMPOSE logs --tail=30 frontend 2>/dev/null || true
        return 1
    fi
}

setup_frontend_local() {
    enter_dir "$FRONTEND_DIR" || return 1

    if [[ ! -d "node_modules" ]]; then
        log_info "Installing npm dependencies..."
        npm install || { log_error "npm install failed"; return 1; }
        log_success "Dependencies installed"
    else
        log_info "node_modules exists, skipping install"
    fi

    [[ ! -f ".env.local" ]] && [[ -f ".env.example" ]] && cp .env.example .env.local

    log_info "Starting Next.js dev server..."
    npm run dev > /dev/null 2>&1 &
    FRONTEND_PID=$!

    sleep 1
    if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
        log_error "Frontend process died immediately"
        return 1
    fi

    if wait_for_health "$FRONTEND_URL" "$TIMEOUT"; then
        log_success "Frontend is ready"
    else
        log_error "Frontend failed to start within ${TIMEOUT}s"
        return 1
    fi
}

# =============================================================================
# E2E Integration Tests
# =============================================================================
run_e2e_tests() {
    log_info "Running E2E integration tests..."

    # Test 1: Login
    local login_url="$API_URL/api/v1/auth/login"
    log_info "Testing login: $login_url"
    http_request POST "$login_url" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\"}"
    assert_http_ok "Login" "$login_url" || return 1

    local access_token
    access_token=$(json_extract "$HTTP_BODY" "access_token")
    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
        log_error "Failed to extract access token"
        echo "Response: $HTTP_BODY"
        return 1
    fi
    log_success "Login successful, got access token"

    # Test 2: /auth/me
    local me_url="$API_URL/api/v1/auth/me"
    log_info "Testing /auth/me: $me_url"
    http_request GET "$me_url" -H "Authorization: Bearer $access_token"
    assert_http_ok "/auth/me" "$me_url" || return 1

    if echo "$HTTP_BODY" | grep -q "$ADMIN_EMAIL"; then
        log_success "/auth/me returns correct user data"
    else
        log_warning "/auth/me response may not contain expected email"
        echo "Response: $HTTP_BODY"
    fi

    # Test 3: Projects
    local projects_url="$API_URL/api/v1/projects"
    log_info "Testing projects: $projects_url"
    http_request GET "$projects_url" -H "Authorization: Bearer $access_token"
    assert_http_ok "Projects" "$projects_url" || return 1

    if echo "$HTTP_BODY" | grep -q "projects"; then
        log_success "Projects endpoint returns data"
    else
        log_warning "Projects response may not contain expected data"
        echo "Response: $HTTP_BODY"
    fi

    # Test 4: Frontend connectivity
    log_info "Testing frontend: $FRONTEND_URL"
    http_request GET "$FRONTEND_URL"
    if [[ "$HTTP_CODE" =~ ^[23] ]]; then
        log_success "Frontend responds (HTTP $HTTP_CODE)"
    else
        log_warning "Frontend not responding (HTTP $HTTP_CODE)"
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo "======================================"
    echo "  Construction Setup Verification"
    echo "======================================"
    echo ""

    switch_docker_context "$TARGET_CONTEXT" || exit 1

    if [[ "$CLEAN_ALL" == true ]]; then
        detect_docker_compose || { log_error "Docker Compose not found"; exit 1; }
        clean_all_docker
        exit 0
    fi

    # Quick rebuild mode - skip full setup
    if [[ -n "$QUICK_REBUILD" ]]; then
        quick_rebuild "$QUICK_REBUILD"
        exit $?
    fi

    local start_time failed=0
    start_time=$(date +%s)

    check_prerequisites || failed=1
    [[ $failed -eq 0 ]] && verify_docker  || failed=1
    [[ $failed -eq 0 ]] && setup_database || failed=1
    [[ $failed -eq 0 ]] && setup_frontend || failed=1
    [[ $failed -eq 0 ]] && run_e2e_tests  || failed=1

    local elapsed=$(($(date +%s) - start_time))

    echo ""
    echo "======================================"
    if [[ $failed -eq 0 ]]; then
        log_success "All verifications passed! (${elapsed}s)"
    else
        log_error "Verification failed! (${elapsed}s)"
    fi
    echo "======================================"
    exit $failed
}

main
