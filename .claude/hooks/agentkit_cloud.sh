#!/usr/bin/env bash
# SessionStart hook: in cloud sessions only, install the AgentKit engineer kit in the background
# (tools/agentkit/cloud-install.sh). Does nothing on a local machine, without AGENTKIT_API_KEY,
# or when the kit is already installed in this container. Never blocks or fails the session.
cat >/dev/null 2>&1 || true
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
[ -n "${AGENTKIT_API_KEY:-}" ] || exit 0
[ -f "$HOME/.agentkit-cloud-installed" ] && exit 0

lock="$HOME/.agentkit-cloud-install.lock"
# A lock older than 10 minutes without the installed marker belongs to an install that died:
# clear it so this session retries.
if [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
  rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true
fi
mkdir "$lock" 2>/dev/null || exit 0

# setsid puts the installer in its own session and process group, so it survives when Claude Code
# cleans up the hook's process group after this script returns (nohup alone only ignores SIGHUP).
setsid -f nohup bash "$CLAUDE_PROJECT_DIR/tools/agentkit/cloud-install.sh" \
  >>"$HOME/.agentkit-cloud-install.log" 2>&1 </dev/null
# Wait (up to 5 s) until the installer has written its pid, i.e. it runs in its own session.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$lock/pid" ] && break
  sleep 0.5
done
exit 0
