#!/usr/bin/env bash
# Phase 8 — install Google Cloud Ops Agent on the VM.
# Runs ON THE VM as root. Idempotent.
#
# Ops Agent ships:
#   - System metrics (CPU, memory, disk, network) → Cloud Monitoring
#   - Default syslog + journald scrape → Cloud Logging
#   - Container stdout/stderr scrape via fluent-bit
#
# Constrained to MemoryMax=256M (per phase-08 risk row "Ops Agent eats VM
# RAM"). Phase 8 only enables 2 alerts: uptime check + disk >85%.
set -euo pipefail

log() { printf '[ops-agent] %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root" >&2; exit 1; }

if /usr/bin/dpkg -s google-cloud-ops-agent >/dev/null 2>&1; then
  log "ops agent already installed: $(/usr/sbin/google-cloud-ops-agent --version 2>/dev/null || dpkg -s google-cloud-ops-agent | grep ^Version)"
else
  log "installing ops agent (Google official installer)"
  /usr/bin/curl -sS -o /tmp/add-ops-agent-repo.sh \
    https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
  /usr/bin/bash /tmp/add-ops-agent-repo.sh --also-install
  /usr/bin/rm -f /tmp/add-ops-agent-repo.sh
fi

# Memory guard via systemd drop-in.
/usr/bin/install -d -m 755 /etc/systemd/system/google-cloud-ops-agent.service.d
cat > /etc/systemd/system/google-cloud-ops-agent.service.d/10-memory-cap.conf <<'EOF'
[Service]
# Cap RAM. Ops Agent typically idles at 80-150 MB; 256 MB gives headroom for
# burst log shipping without endangering the 8 GB VM under load.
MemoryMax=256M
MemoryHigh=200M
EOF

# Optional: enrich Docker container logs with service labels via Ops Agent
# config. If you have specific service names ("api", "worker", "frontend"…)
# you want labelled, edit /etc/google-cloud-ops-agent/config.yaml. The
# default config already collects journald + syslog which covers Docker-via-
# systemd output and is fine for v1.

/usr/bin/systemctl daemon-reload
/usr/bin/systemctl enable --now google-cloud-ops-agent

log "verifying agent is shipping data (give it 30s, then check Cloud Logging)"
/usr/bin/systemctl is-active google-cloud-ops-agent
log "  log query (in Console):"
log "    resource.type=\"gce_instance\" resource.labels.instance_id=\"$(/usr/bin/curl -sH 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/id)\""
log "  metrics query:"
log "    https://console.cloud.google.com/monitoring/dashboards"
