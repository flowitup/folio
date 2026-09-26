#!/usr/bin/env bash
# Forced command of Folio's CI deploy key. Root's authorized_keys holds that key as
#   restrict,command="/opt/folio/scripts/ci-deploy.sh" ssh-ed25519 <key> folio-ci-deploy
# so sshd runs this script whatever the client asks for, with the request in SSH_ORIGINAL_COMMAND
# (unset for a plain shell request). The one request it accepts is
#   deploy <api|frontend> <sha: 7-40 lowercase hex> <sha256 of the host files: 64 lowercase hex>
# with a short-lived Artifact Registry access token as the first line of stdin. A shell, any other
# command, sftp or scp, and a deploy in any other shape are refused before anything runs.
#
# The host files -- this script, deploy-runner.sh, wait-healthy.sh, rollback.sh and both compose
# files -- are installed by the owner, never through this key (scripts/README.md, "Installing the
# host files"), and a deploy refuses to start while they differ from the workflow's checkout. The
# deploy itself is the installed deploy-runner.sh, run with a clean environment and a throwaway
# Docker config that holds the registry login for this deploy only.
set -euo pipefail
export LC_ALL=C   # sshd forwards the client's LANG/LC_* (AcceptEnv): pin the locale before any match
umask 077
readonly REGISTRY=europe-west1-docker.pkg.dev
DIR=$(dirname "$0")   # from the script's own path, never from the environment
readonly DIR
# Hashed in this order; both deploy workflows hash the same files in the same order.
HOST_FILES=("$DIR/ci-deploy.sh" "$DIR/deploy-runner.sh" "$DIR/wait-healthy.sh" "$DIR/rollback.sh"
            "$DIR/../docker-compose.yml" "$DIR/../docker-compose.prod.yml")
log()    { logger -t folio-ci-deploy -- "$*"; printf '%s\n' "$*" >&2 2>/dev/null || true; }
reject() { log "rejected: $1"; exit 2; }
clean()  { env -i PATH="$PATH" HOME=/root LC_ALL=C "$@"; }   # no variable of the SSH session reaches a child

[[ "${SSH_ORIGINAL_COMMAND-}" =~ ^deploy\ (api|frontend)\ ([0-9a-f]{7,40})\ ([0-9a-f]{64})$ ]] \
  || reject "unexpected command"
svc=${BASH_REMATCH[1]} sha=${BASH_REMATCH[2]} expected=${BASH_REMATCH[3]}

actual=$(cat "${HOST_FILES[@]}" 2>/dev/null | sha256sum) || reject "host files are missing"
actual=${actual%% *}
[[ "$actual" == "$expected" ]] \
  || reject "host files differ from the workflow's checkout (host $actual, workflow $expected); install them first"

IFS= read -r -t 15 token && [[ -n "$token" ]] || reject "no registry token on stdin"

cfg=$(mktemp -d); trap 'rm -rf "$cfg"' EXIT   # throwaway Docker config; root's ~/.docker is never touched
printf '%s' "$token" | clean docker --config "$cfg" login -u oauth2accesstoken --password-stdin "$REGISTRY" >/dev/null \
  || { log "registry login failed"; exit 1; }
unset token
log "accepted: deploy $svc $sha"
status=0
clean DOCKER_CONFIG="$cfg" "$DIR/deploy-runner.sh" "$sha" "$svc" </dev/null || status=$?
if (( status == 0 )); then log "deployed $svc $sha"; else log "deploy of $svc $sha failed (exit $status)"; fi
exit "$status"
