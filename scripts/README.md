# Scripts

## verify-setup.sh

Full E2E verification script for the Construction project. Validates Docker services, database, frontend, and authentication flow.

### Usage

```bash
./verify-setup.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--cleanup` | Stop all services after verification |
| `--cleanall` | Remove all Docker containers, volumes, caches, and storage |
| `--context NAME` | Docker context to use (default: `default`) |
| `--host IP` | Remote host IP (required with `--context`) |
| `--timeout N` | Set timeout in seconds (default: `120`) |
| `--help, -h` | Show help message |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_EMAIL` | `admin@example.com` | Admin email for seeding |
| `ADMIN_PASSWORD` | `password123` | Admin password for seeding |

### Verification Steps

1. **Prerequisites** - Checks docker, node, npm, curl, docker-compose
2. **Docker Services** - Starts containers, waits for DB/Redis/API health
3. **Database Setup** - Runs migrations, seeds admin user and projects
4. **Frontend Setup** - Installs deps (if needed), starts Next.js dev server
5. **E2E Tests** - Login, /auth/me, projects endpoint, frontend connectivity

### Examples

```bash
# Basic verification (services stay running)
./verify-setup.sh

# Verify then stop all services
./verify-setup.sh --cleanup

# Full cleanup (remove all Docker artifacts)
./verify-setup.sh --cleanall

# Remote context with custom timeout
./verify-setup.sh --context remote-server --host 192.168.1.100 --timeout 180

# Custom admin credentials
ADMIN_EMAIL="test@example.com" ADMIN_PASSWORD="secret" ./verify-setup.sh
```

### Exit Codes

- `0` - All verifications passed
- `1` - Verification failed or missing prerequisites
