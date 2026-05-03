# GCP Single-VM Deployment Architecture — Planning Sprint

**Date**: 2026-04-29 23:31 UTC
**Severity**: Medium (pre-production planning)
**Component**: Infrastructure / Deployment
**Status**: DONE

## What Happened

Brainstormed + planned production deploy for Folio 6-service stack (Flask API + RQ worker + Postgres 16 + Redis 7 + MinIO + Next.js SSR) on GCP under real-world constraints: $100/mo AI Ultra credit (≤12 mo), commercial workload w/ paying customers, eu-west1 region.

Evaluated 3 options with line-item pricing. User chose **Option A** (single e2-standard-2 VM, all services in Docker, ~$80/mo) over recommended **Option B** (Option A + Cloud SQL Postgres = ~$135/mo). Documented architectural decisions and created full 11-phase deployment plan.

## The Brutal Truth

**The credit cliff is real.** $100/mo free tier isn't infinite — month 13 hits with no warning. Architecture must survive gracefully when credit expires. Option B remains the "right" answer for paying customers; Option A is a conscious tradeoff that trades ops risk (self-managed Postgres) for staying inside the credit window. This decision will hurt when the first DB incident occurs at 3am. Document it now to prevent re-litigating later.

Cloud-native dogma (Cloud Run) would have added 3× cost + forced a poor fit (request-driven runtime for long-running RQ worker). Sometimes the simple answer wins.

## Technical Details

### Chosen Architecture (Option A)
- **Compute**: e2-standard-2 (2 vCPU, 8 GB RAM), Debian 12
- **Storage**: named Docker volumes (Postgres, Redis, MinIO) on pd-balanced
- **Networking**: Cloudflare Tunnel (`cloudflared`) — zero inbound firewall rules, no static IP needed, $0 cost
- **Deploy**: GitHub Actions → Artifact Registry → SSH → `docker compose pull`
- **Backup**: pg_dump daily + WAL archive (GCS), MinIO mirror (GCS), weekly disk snapshots
- **Monitoring**: Cloud Logging + uptime check + Ops Agent + log-based alerts (free tier)

**Monthly cost breakdown:**
- VM + disk + snapshots: ~$60
- Egress (200 GB/mo, Cloudflare caches static): ~$17
- AR + GCS backups: ~$0.70
- **Total**: ~$80/mo (leaves ~$20 headroom in credit)
- **Month 13 (no credit)**: $80/mo out of pocket

### Rejected Approaches
- **Option B** (~$135/mo): Cloud SQL Postgres + GCS bucket. Better for commercial (managed backups, PITR, no patching), but $35/mo over credit. User accepted self-managed-DB ops risk.
- **Option C** (~$240/mo): Cloud Run + Cloud SQL + Memorystore. Overkill; Cloud Run is a poor fit for the RQ worker (request-driven runtime vs. long-running queue consumer).

## What We Tried

1. **Pricing analysis**: Modeled 3 deployment topologies with GCP list prices (no SUD). Compared to constraints.
2. **Architecture options**: Serverless (rejected for cost + RQ worker fit), managed services (over budget), bare metal (not GCP).
3. **Networking**: Evaluated static IP + firewall rules vs. Cloudflare Tunnel. Tunnel eliminates IP cost + improves security posture.
4. **Backup strategy**: Designed RPO ≤ 5 min (WAL archive) + RTO ≤ 30 min (quarterly restore drill on sidecar VM).

## Root Cause Analysis

**Why Option A instead of B?** User's constraint: stay inside $100/mo AI Ultra credit. Cloud SQL Postgres (~$35/mo) blows budget; self-managed DB on the VM stays within. This is not a technical choice — it's a business constraint (credit funding). The risk (DB corruption, restore at 3am) is explicit and accepted.

**Why not Cloud Run?** RQ worker is a 24/7 background queue consumer. Cloud Run charges per request; a long-running job looks like a hung request. Textbook anti-pattern. Single VM + Docker is simpler + cheaper + better fit.

## Lessons Learned

1. **Free tier ≠ free forever.** AI Ultra credit expires month 13. Architecture for both credit-funded AND post-credit cost reality. Set calendar reminder month 11 to evaluate Option B migration (or accept $80/mo bill).

2. **Cloud-native ≠ best solution.** Cloud Run is the textbook answer for microservices; RQ worker + 6-service state-heavy stack makes it wrong. Sometimes a VM wins on cost + simplicity. Don't blindly follow patterns.

3. **Cloudflare Tunnel removes surface.** No static IP reservation ($2.92/mo), no public SSH port, no inbound firewall rules. Security + cost win. Use it.

4. **Self-managed Postgres is a time bomb.** Accepting this risk explicitly (not accidentally). When it breaks, the cost of restoring will be 10× the $35/mo Cloud SQL would have been. Document for retrospective.

## Next Steps

**Before Phase 1 (GCP Bootstrap):**
- [ ] Confirm GCP project name + billing account (new or existing?)
- [ ] Confirm domain already at Cloudflare (DNS hosted there)?
- [ ] Outbound SMTP requirements? (API needs to send transactional emails; affects firewall egress)
- [ ] Staging environment needed? (Option: separate VM ≈ +$50/mo, or namespaced compose on prod)
- [ ] Month-13 cliff plan: automatic Option-B migration or accept $80/mo bill?

**Plan structure** (ready to execute):
- 11 phases spanning GCP bootstrap → Cloudflare wiring → CI/CD → backups → observability → first deploy → restore drill
- Phase files at: `/Users/sweet-home/workspaces/folio/.claude/worktrees/clever-elion-04ea3a/plans/260429-2303-gcp-single-vm-deploy/phase-0X-*.md`
- Full plan at: `plans/260429-2303-gcp-single-vm-deploy/plan.md`

**Artifacts:**
- Brainstorm report: `plans/reports/brainstorm-260429-2303-gcp-deploy-strategy.md`
- Plan dir: `plans/260429-2303-gcp-single-vm-deploy/`

---

**Status**: DONE_WITH_CONCERNS

**Concerns**: Self-managed Postgres risk is real; we've documented it, but pain will surface during restore events or data corruption. Option B should be revisited at 50+ paying users or first DB scare.

**Unresolved**: GCP project name, domain status, SMTP provider, staging y/n, month-13 funding plan (inputs needed before Phase 1).
