#!/usr/bin/env bash
# Phase 3 — VM bootstrap. Run on the VM (not on the operator's laptop).
# Idempotent: every step checks state before mutating, so re-runs are safe.
#
# Transfer + execute:
#   gcloud compute scp infra/gcp/cloud-init/startup.sh \
#     flowitup-folio-prod-1:/tmp/startup.sh \
#     --tunnel-through-iap --zone=europe-west1-b
#   gcloud compute ssh flowitup-folio-prod-1 --tunnel-through-iap \
#     --zone=europe-west1-b -- 'sudo bash /tmp/startup.sh'
#
# Skipped per Y1 (YAGNI cuts): fail2ban (no public SSH on Tunnel-only deploy).
set -euo pipefail

DATA_DEV=/dev/disk/by-id/google-folio-data
DOCKER_ROOT=/var/lib/docker
APP_DIR=/opt/folio
log() { printf '[bootstrap] %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "ERROR: run as root (sudo bash $0)" >&2; exit 1; }

# 1. Format + mount data disk at /var/lib/docker BEFORE Docker installs.
# Docker installs onto the already-mounted disk, no data movement needed.
[[ -e $DATA_DEV ]] || { echo "ERROR: data disk $DATA_DEV not present" >&2; exit 1; }
if ! /usr/sbin/blkid "$DATA_DEV" >/dev/null 2>&1; then
  log "formatting $DATA_DEV as ext4 (blank disk detected)"
  /usr/sbin/mkfs.ext4 -F "$DATA_DEV"
fi
mkdir -p "$DOCKER_ROOT"
if ! /usr/bin/mountpoint -q "$DOCKER_ROOT"; then
  log "mounting $DATA_DEV → $DOCKER_ROOT"
  mount "$DATA_DEV" "$DOCKER_ROOT"
fi
UUID=$(/usr/sbin/blkid -s UUID -o value "$DATA_DEV")
if ! grep -q "$UUID" /etc/fstab; then
  log "persisting mount via /etc/fstab (UUID=$UUID)"
  printf 'UUID=%s %s ext4 defaults,nofail,discard 0 2\n' "$UUID" "$DOCKER_ROOT" >> /etc/fstab
fi

# 2. Base packages.
export DEBIAN_FRONTEND=noninteractive
log "apt update + base packages"
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release unattended-upgrades cron

# 3. Docker Engine (official Ubuntu repo).
if ! command -v docker >/dev/null 2>&1; then
  log "installing Docker Engine"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "$(lsb_release -cs)" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  log "Docker already installed: $(docker --version)"
fi

# 4. Docker daemon config: explicit data-root + JSON-file log rotation + live-restore.
# Hash-compare to avoid bouncing the daemon on every re-run (changing data-root
# is incompatible with live-restore, so only restart when the file actually changed).
mkdir -p /etc/docker
desired=$(mktemp)
cat > "$desired" <<EOF
{
  "data-root": "${DOCKER_ROOT}",
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
systemctl enable -q docker
if ! /usr/bin/cmp -s "$desired" /etc/docker/daemon.json 2>/dev/null; then
  log "daemon.json changed → restart docker"
  install -m 644 "$desired" /etc/docker/daemon.json
  systemctl restart docker
else
  log "daemon.json unchanged; not bouncing docker"
fi
rm -f "$desired"

# 4b. Replace snap gcloud with apt gcloud.
# Ubuntu 24.04 GCE images ship google-cloud-cli as a snap. Snap apps need to
# write under /root/snap, which is blocked by ProtectHome=true on hardened
# systemd units (e.g. folio-render-env.service). Apt gcloud writes to /etc and
# /var/lib instead, plays nicely with ProtectSystem=strict + ProtectHome=true.
if [[ -e /snap/bin/gcloud ]] || snap list google-cloud-cli >/dev/null 2>&1; then
  log "removing snap gcloud (incompatible with hardened systemd units)"
  snap remove google-cloud-cli 2>/dev/null || true
  snap remove google-cloud-sdk 2>/dev/null || true
fi
if ! dpkg -s google-cloud-cli >/dev/null 2>&1; then
  log "installing apt gcloud"
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/cloud.google.gpg
  printf 'deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main\n' \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  apt-get update -qq
  apt-get install -y -qq google-cloud-cli
else
  log "apt gcloud already present: $(gcloud --version 2>/dev/null | head -1)"
fi

# 5. cloudflared (configured against a Tunnel in phase 4).
if ! command -v cloudflared >/dev/null 2>&1; then
  log "installing cloudflared"
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/cloudflare-main.gpg
  printf 'deb [signed-by=/etc/apt/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared %s main\n' \
    "$(lsb_release -cs)" > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -qq
  apt-get install -y -qq cloudflared
else
  log "cloudflared already installed: $(cloudflared --version | head -1)"
fi

# 6. SSH hardening drop-in (belt + braces; OS Login already enforces most of these).
cat > /etc/ssh/sshd_config.d/99-folio.conf <<'EOF'
# Folio prod hardening — supplemental to OS Login defaults.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
X11Forwarding no
EOF
systemctl reload ssh 2>/dev/null || systemctl reload sshd

# 7. Unattended security upgrades — NO auto-reboot (Y1: manual maintenance windows).
cat > /etc/apt/apt.conf.d/51folio-unattended <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable -q --now unattended-upgrades

# 8. Image-prune cron — bound disk usage from accumulated AR pulls.
cat > /etc/cron.weekly/folio-image-prune <<'EOF'
#!/bin/sh
# Truncate (not append) — avoids unbounded log growth between reviews.
exec >/var/log/folio-image-prune.log 2>&1
date -u +'[%Y-%m-%dT%H:%M:%SZ] image prune start'
docker image prune -af --filter 'until=168h'
date -u +'[%Y-%m-%dT%H:%M:%SZ] image prune end'
EOF
chmod 755 /etc/cron.weekly/folio-image-prune

# 9. App dir for compose files + .env (rendered in phase 6).
mkdir -p "$APP_DIR"
chmod 755 "$APP_DIR"

log "done."
log "  Docker root:  $(docker info --format '{{.DockerRootDir}}')"
log "  Disk:         $(df -h "$DOCKER_ROOT" | tail -1)"
log "  Compose:      $(docker compose version --short)"
log "  cloudflared:  $(cloudflared --version 2>&1 | head -1)"
log "Next: add your OS Login user to the docker group (one-time, per user):"
log "  sudo usermod -aG docker \$USER && newgrp docker"
