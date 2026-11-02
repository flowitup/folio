#!/usr/bin/env bash
# Installs the AgentKit ("ak") engineer kit into a Claude Code cloud session's own ~/.claude,
# so /ak:* skills work in project threads the same way they do on the owner's Mac.
#
# Nothing from the kit is committed to this repo: AgentKit is a paid, per-user licence that
# forbids redistributing the kit, so every cloud session downloads it with the owner's key.
#
# Started in the background by .claude/hooks/agentkit_cloud.sh (SessionStart). Needs:
#   AGENTKIT_API_KEY   the owner's AgentKit API key, saved in the cloud environment's variables.
# Optional:
#   AGENTKIT_CLOUD_HOOKS=1  also keep AgentKit's global hooks + status line. Off by default:
#                           the kit's hooks are written for the owner's Mac and some of them
#                           block or rewrite tool calls (scout-block, context-firewall), which
#                           would get in the way of thread work. Skills and agents work without them.
# Log: ~/.agentkit-cloud-install.log
set -euo pipefail

AK_PIN_VERSION="3.0.0"
case "$(uname -m)" in
  x86_64|amd64)  arch=amd64; sha=8f4855d4fd58bac6deb8c9d66bf46bad187a93459cb46a66ca4e830dc5558805 ;;
  aarch64|arm64) arch=arm64; sha=40fb69e74bacf8c3c27ea6ec6eefb176cd8f3d8972525f2e0176e5f7c3728928 ;;
  *) echo "agentkit: unsupported CPU $(uname -m)"; exit 1 ;;
esac
# Pins copied from the official installer (https://releases.agentkit.best/install.sh, stable channel).
url="https://releases.agentkit.best/binaries/${AK_PIN_VERSION}/ak_${AK_PIN_VERSION}_linux_${arch}.tar.gz"

lock="$HOME/.agentkit-cloud-install.lock"
tmp="$(mktemp -d)"
echo $$ > "$lock/pid" 2>/dev/null || true
trap 'rm -rf "$tmp"; rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true' EXIT
trap 'echo "agentkit: stopped by a signal"; exit 1' HUP INT TERM
echo "agentkit: install started $(date -u +%FT%TZ)"

bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"
export PATH="$bin_dir:$PATH"

if ! command -v ak >/dev/null 2>&1; then
  echo "agentkit: downloading ak ${AK_PIN_VERSION} (linux/${arch})"
  curl -fsSL --retry 3 -o "$tmp/ak.tgz" "$url"
  echo "${sha}  $tmp/ak.tgz" | sha256sum -c - >/dev/null
  # Same rule as the official installer: exactly one entry named "ak", no unsafe paths.
  entries="$(tar -tzf "$tmp/ak.tgz")"
  if printf '%s\n' "$entries" | grep -Eq '^/|(^|/)\.\.(/|$)'; then
    echo "agentkit: archive has an unsafe path"; exit 1
  fi
  [ "$(printf '%s\n' "$entries" | sed 's#^\./##' | grep -cx 'ak')" = "1" ] || { echo "agentkit: archive must hold one ak binary"; exit 1; }
  entry="$(printf '%s\n' "$entries" | grep -E '^(\./)?ak$')"
  tar -xOzf "$tmp/ak.tgz" -- "$entry" > "$tmp/ak"
  install -m 755 "$tmp/ak" "$bin_dir/ak"
fi
ak --version

# Log in with the key from the environment; --api-key-stdin keeps it out of the process list.
printf '%s' "$AGENTKIT_API_KEY" | ak login --api-key-stdin --no-interactive

# Run ak from a temp dir, never from ~: there project scope and ~/.claude are the same folder.
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
had_settings=0
if [ -f "$settings" ]; then cp "$settings" "$tmp/settings.before.json"; had_settings=1; fi

echo "agentkit: installing the engineer kit"
( cd "$tmp" && ak kit init engineer --global --force --yes --no-interactive </dev/null ) \
  || ( cd "$tmp" && ak kit init engineer --global --force --yes </dev/null )

if [ "${AGENTKIT_CLOUD_HOOKS:-0}" != "1" ]; then
  # Keep skills, agents and rules; put the user settings (hooks, status line) back as they were.
  if [ "$had_settings" = "1" ]; then cp "$tmp/settings.before.json" "$settings"; else rm -f "$settings"; fi
  echo "agentkit: skills installed; AgentKit hooks left off (set AGENTKIT_CLOUD_HOOKS=1 to keep them)"
fi

skills="$(ls -d "$HOME"/.claude/skills/ak-* 2>/dev/null | wc -l)"
echo "agentkit: done, ${skills} ak skills in ~/.claude/skills"
touch "$HOME/.agentkit-cloud-installed"
