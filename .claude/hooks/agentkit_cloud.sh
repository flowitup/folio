#!/usr/bin/env bash
# SessionStart hook: in cloud sessions only, install the AgentKit engineer kit in the background
# (tools/agentkit/cloud-install.sh). Does nothing on a local machine, without AGENTKIT_API_KEY,
# or when the kit is already installed in this container. Never blocks or fails the session.
cat >/dev/null 2>&1 || true
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
[ -n "${AGENTKIT_API_KEY:-}" ] || exit 0
[ -f "$HOME/.agentkit-cloud-installed" ] && exit 0

log="$HOME/.agentkit-cloud-install.log"
lock="$HOME/.agentkit-cloud-install.lock"
# The lock is stale when the install that took it is gone: its pid is no longer a running
# cloud-install.sh, or it never wrote a pid and the lock is over a minute old. $HOME can carry
# over from an earlier container, so a lock left by a killed install must not block this one.
if [ -d "$lock" ]; then
  pid="$(cat "$lock/pid" 2>/dev/null || true)"
  stale=0
  if [ -n "$pid" ]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'cloud-install.sh' || stale=1
  elif [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    stale=1
  fi
  if [ "$stale" = "1" ]; then
    echo "agentkit hook: clearing a stale lock ($(date -u +%FT%TZ))" >> "$log"
    rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true
  fi
fi
if ! mkdir "$lock" 2>/dev/null; then
  echo "agentkit hook: an install is already running, skipped ($(date -u +%FT%TZ))" >> "$log"
  exit 0
fi

# setsid puts the installer in its own session and process group, so it survives when Claude Code
# cleans up the hook's process group after this script returns (nohup alone only ignores SIGHUP).
setsid -f nohup bash "$CLAUDE_PROJECT_DIR/tools/agentkit/cloud-install.sh" \
  >>"$log" 2>&1 </dev/null
# Wait (up to 5 s) until the installer has written its pid, i.e. it runs in its own session.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$lock/pid" ] && break
  sleep 0.5
done
exit 0
