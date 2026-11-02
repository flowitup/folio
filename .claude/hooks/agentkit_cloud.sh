#!/usr/bin/env bash
# SessionStart hook: in cloud sessions only, install the AgentKit engineer kit in the background
# (tools/agentkit/cloud-install.sh). Does nothing on a local machine, without AGENTKIT_API_KEY,
# or when the kit is already installed in this container. Never blocks or fails the session.
cat >/dev/null 2>&1 || true
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
[ -n "${AGENTKIT_API_KEY:-}" ] || exit 0
[ -f "$HOME/.agentkit-cloud-installed" ] && exit 0
mkdir "$HOME/.agentkit-cloud-install.lock" 2>/dev/null || exit 0
nohup bash "$CLAUDE_PROJECT_DIR/tools/agentkit/cloud-install.sh" \
  >"$HOME/.agentkit-cloud-install.log" 2>&1 </dev/null &
exit 0
