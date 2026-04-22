# Deployment Guide

**Last Updated:** 2026-01-28
**Status:** Blueprint (not yet implemented)

## Deployment Options

### Development Environment

**Local Development with Docker:**
```bash
# Start all services
docker-compose up -d

# Verify setup
./scripts/verify-setup.sh

# Access
Frontend: http://localhost:3000
Backend: http://localhost:5000/api/v1
```

**Local Development without Docker:**
```bash
# Backend
cd construction-back-end
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
flask db upgrade
python run.py

# Frontend (new terminal)
cd construction-front-end
npm install
npm run dev
```

---

## Production Deployment

### Option 1: Cloud-Native (Recommended)

#### Frontend: Vercel

**Advantages:**
- Zero-config Next.js deployment
- Automatic scaling & CDN
- Built-in analytics & monitoring
- Easy SSL/TLS
- $0 startup cost (free tier available)

**Steps:**
1. Push code to GitHub
2. Connect repository to Vercel
3. Set environment variables:
   - `NEXT_PUBLIC_API_URL` - Backend URL
   - `NODE_ENV` - "production"
4. Deploy (automatic on push)

**Configuration:**
```json
{
  "buildCommand": "npm run build",
  "outputDirectory": ".next",
  "env": {
    "NEXT_PUBLIC_API_URL": "@api_url"
  }
}
```

**Cost:** ~$0-20/month

#### Backend: Google Cloud Run / AWS ECS

**Google Cloud Run:**

**Dockerfile Setup:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "app:create_app()"]
```

**Deploy:**
```bash
# Build & push to Container Registry
gcloud builds submit --tag gcr.io/PROJECT_ID/construction-api

# Deploy
gcloud run deploy construction-api \
  --image gcr.io/PROJECT_ID/construction-api \
  --platform managed \
  --region us-central1 \
  --set-env-vars DATABASE_URL=$DB_URL,REDIS_URL=$REDIS_URL
```

**Cost:** ~$10-50/month (depends on traffic)

**AWS ECS:**

**Task Definition:**
```json
{
  "name": "construction-api",
  "image": "123456789.dkr.ecr.us-east-1.amazonaws.com/construction-api:latest",
  "memory": 512,
  "cpu": 256,
  "environment": [
    {"name": "DATABASE_URL", "value": "postgres://..."},
    {"name": "REDIS_URL", "value": "redis://..."}
  ],
  "portMappings": [{"containerPort": 8000}]
}
```

**Cost:** ~$20-100/month (depends on instance size)

#### Database: AWS RDS PostgreSQL

**Setup:**
```bash
# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier construction-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username admin \
  --master-user-password <secure-password> \
  --allocated-storage 20
```

**Configuration:**
- **Version:** PostgreSQL 15+
- **Instance:** db.t3.micro (free tier eligible)
- **Backup:** Daily backups, 7-day retention
- **Multi-AZ:** Enable for production HA
- **Encryption:** Enable at-rest & in-transit

**Connection String:**
```
postgresql://admin:password@construction-db.c3j4k9.us-east-1.rds.amazonaws.com:5432/construction
```

**Cost:** ~$15-50/month (free tier up to 750 hours/month)

#### Cache: AWS ElastiCache Redis

**Setup:**
```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id construction-redis \
  --cache-node-type cache.t3.micro \
  --engine redis \
  --num-cache-nodes 1
```

**Configuration:**
- **Version:** Redis 7+
- **Node Type:** cache.t3.micro
- **Backup:** Enable daily snapshots
- **Multi-AZ:** Disabled for dev (enable for prod)

**Connection String:**
```
redis://construction-redis.abc123.ng.0001.use1.cache.amazonaws.com:6379
```

**Cost:** ~$10-30/month

#### Domain & SSL

**Route 53 (AWS):**
```bash
# Create hosted zone
aws route53 create-hosted-zone \
  --name construction.example.com \
  --caller-reference $(date +%s)

# Create DNS records
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch file://dns-changes.json
```

**SSL/TLS:**
- **Vercel:** Automatic (Let's Encrypt)
- **Cloud Run:** Automatic (Google-managed)
- **ECS:** Use AWS Certificate Manager (free)

**Cost:** Free

---

### Option 2: Self-Hosted (Docker Swarm / Kubernetes)

#### Docker Compose (Single Server)

**Production compose file:**
```yaml
version: '3.8'

services:
  api:
    image: construction-api:latest
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/construction
      REDIS_URL: redis://redis:6379
      FLASK_ENV: production
      JWT_SECRET_KEY: ${JWT_SECRET_KEY}
    depends_on:
      - db
      - redis
    restart: always
    deploy:
      replicas: 2

  frontend:
    image: construction-frontend:latest
    ports:
      - "80:3000"
    environment:
      NEXT_PUBLIC_API_URL: https://api.example.com
    restart: always

  db:
    image: postgres:15-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: construction
    restart: always

  redis:
    image: redis:7-alpine
    restart: always

volumes:
  postgres_data:
```

**Deploy:**
```bash
docker stack deploy -c docker-compose.yml construction
```

**Cost:** EC2 instance ($10-30/month)

#### Kubernetes (Multi-Node)

**Helm Chart Structure:**
```
helm/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── configmap.yaml
```

**Deploy:**
```bash
helm install construction ./helm \
  --set image.tag=latest \
  --set database.url=$DATABASE_URL
```

**Cost:** $20-100+/month (depends on cluster size)

---

## Environment Configuration

### Required Environment Variables

#### Backend (.env)
```env
# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/construction

# Redis
REDIS_URL=redis://localhost:6379/0

# JWT
JWT_SECRET_KEY=<64-character-random-string>
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRES=1800
JWT_REFRESH_TOKEN_EXPIRES=604800

# Flask
FLASK_ENV=production
SECRET_KEY=<32-character-random-string>

# CORS
CORS_ORIGINS=https://construction.example.com

# Email (future)
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

**Generate Secrets:**
```bash
python -c "import secrets; print(secrets.token_hex(32))"  # JWT_SECRET_KEY
python -c "import secrets; print(secrets.token_hex(16))"  # SECRET_KEY
```

#### Frontend (.env.local)
```env
# API
NEXT_PUBLIC_API_URL=https://api.example.com

# Environment
NODE_ENV=production

# Optional Analytics
NEXT_PUBLIC_GA_ID=G-XXXXXXXXXX
```

---

## Pre-Deployment Checklist

### Security
- [ ] Verify all secrets are environment variables (not hardcoded)
- [ ] Enable HTTPS on all endpoints
- [ ] Set secure cookie flags (Secure, HttpOnly, SameSite)
- [ ] Review CORS allowed origins
- [ ] Enable rate limiting in production config
- [ ] Set strong JWT_SECRET_KEY (64+ chars)
- [ ] Enable database encryption at rest
- [ ] Set up firewall rules (restrict DB access)

### Performance
- [ ] Configure database connection pooling
- [ ] Set up Redis caching
- [ ] Enable CDN for static assets
- [ ] Optimize database queries (add indexes)
- [ ] Configure horizontal scaling
- [ ] Set up load balancing

### Monitoring
- [ ] Set up application logging (CloudWatch / ELK)
- [ ] Configure health checks
- [ ] Set up uptime monitoring (pingdom, datadog)
- [ ] Create alerts for errors & slow queries
- [ ] Set up performance monitoring (New Relic, Datadog)

### Backup & Recovery
- [ ] Enable database automated backups (daily)
- [ ] Test restore procedure
- [ ] Set backup retention (7-30 days)
- [ ] Document disaster recovery plan

### DNS & Domain
- [ ] Register domain
- [ ] Configure DNS records (A, CNAME, MX)
- [ ] Set up SSL certificate
- [ ] Enable DNSSEC (optional)

---

## Deployment Procedure

### Step 1: Database Migration
```bash
# Connect to production database
export DATABASE_URL=<production-db-url>

# Run migrations
flask db upgrade

# Verify
psql $DATABASE_URL -c "SELECT version();"
```

### Step 2: Backend Deployment

**Cloud Run:**
```bash
gcloud run deploy construction-api \
  --source . \
  --set-env-vars DATABASE_URL=$DB_URL,REDIS_URL=$REDIS_URL
```

**Docker:**
```bash
docker build -t construction-api:latest .
docker push <registry>/construction-api:latest
docker service update --image construction-api:latest construction_api
```

### Step 3: Frontend Deployment

**Vercel:**
```bash
npm run build
vercel deploy --prod
```

**Self-hosted:**
```bash
npm run build
npm start  # or: pm2 start npm --name "frontend"
```

### Step 4: Verification

```bash
# Test API
curl https://api.example.com/api/v1/auth/me \
  -H "Authorization: Bearer $TOKEN"

# Test Frontend
curl https://example.com | grep -i "construction"

# Health check
curl https://api.example.com/health
```

---

## Scaling Strategy

### Horizontal Scaling (Multiple Instances)

**Backend:**
- Deploy multiple API instances behind load balancer
- Use Redis for session state (shared across instances)
- Database connection pooling (PgBouncer)

**Frontend:**
- Deploy multiple Next.js instances
- Load balance via reverse proxy (nginx, Cloudflare)
- Static assets served via CDN

### Vertical Scaling (Larger Instances)

- Increase backend instance CPU/memory
- Upgrade database instance class
- Increase Redis memory

### Cost Optimization

- Use auto-scaling based on CPU usage
- Schedule down during off-peak hours
- Use reserved instances for predictable baseline
- Monitor & optimize slow queries

---

## Monitoring & Alerts

### Key Metrics to Monitor

| Metric | Threshold | Action |
|--------|-----------|--------|
| API Response Time p95 | >500ms | Investigate query perf |
| Error Rate | >0.5% | Check logs |
| Database Connections | >80% | Scale up or optimize |
| Redis Memory | >80% | Increase cache capacity |
| Uptime | <99.5% | Review logs |

### Alert Configuration

**Backend Errors:**
```
Alert when error_rate > 1% for 5 minutes
Notify: Slack #alerts, PagerDuty
```

**Database Latency:**
```
Alert when db_query_time_p95 > 500ms for 10 minutes
Notify: Slack #alerts
```

**Memory Usage:**
```
Alert when redis_memory_used > 80% of allocated
Notify: Slack #ops
```

---

## Rollback Procedure

### Rollback to Previous Version
```bash
# Get previous image version
docker images construction-api | head -3

# Rollback
docker service update --image <previous-version> construction_api

# Verify
docker service ps construction_api
```

### Database Rollback
```bash
# Get migration history
flask db history

# Rollback one migration
flask db downgrade -1

# Verify
flask db current
```

---

## Cost Estimation

### Cloud-Native (AWS + Vercel)

| Component | Tier | Cost |
|-----------|------|------|
| Vercel Frontend | Pro | $20/mo |
| ECS Backend | t3.small (2 instances) | $60/mo |
| RDS PostgreSQL | db.t3.micro | $15/mo |
| ElastiCache Redis | cache.t3.micro | $15/mo |
| Route 53 + CloudFront | - | $5/mo |
| **Total** | - | **$115/mo** |

### Self-Hosted (Single Server)

| Component | Tier | Cost |
|-----------|------|------|
| EC2 Instance | t3.medium | $35/mo |
| RDS PostgreSQL | db.t3.micro | $15/mo |
| ElastiCache Redis | cache.t3.micro | $15/mo |
| Domain + DNS | Route 53 | $1/mo |
| **Total** | - | **$66/mo** |

---

## Troubleshooting Deployment Issues

**502 Bad Gateway**
- Check if backend services are running: `docker ps`
- Check logs: `docker logs <container-id>`
- Verify database connection: `psql $DATABASE_URL`

**Database connection errors**
- Check security group rules (allow API instance to access DB)
- Verify DATABASE_URL format
- Check network connectivity: `nc -zv db.example.com 5432`

**Static assets not loading**
- Verify CDN is configured
- Check CORS headers: `curl -i https://api.example.com/static/...`
- Clear CDN cache if using Cloudflare

---

## Future Deployment Improvements

- [ ] Kubernetes cluster for auto-scaling
- [ ] GitOps (ArgoCD) for continuous deployment
- [ ] Infrastructure as Code (Terraform)
- [ ] Blue-green deployments for zero-downtime updates
- [ ] Multi-region setup for disaster recovery
