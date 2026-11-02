# AgentKit (ak) in cloud sessions

The owner uses the AgentKit engineer kit (`ak`, skills invoked as `/ak:*`) on their Mac.
These files make the same kit available in Claude Code cloud sessions of this project.

**Why the kit is not committed here.** AgentKit is a paid, per-user licence whose terms forbid
redistributing the kit or sharing it with other people, and a few bundled skills
(`ak-document-skills`) are proprietary to Anthropic. So the repo only holds an installer:
every cloud session downloads the kit itself, logged in with the owner's own API key.

## How it works

1. `.claude/hooks/agentkit_cloud.sh` runs at SessionStart. It does nothing on a local machine
   (`CLAUDE_CODE_REMOTE` is not `true`), when `AGENTKIT_API_KEY` is not set, or when the kit
   is already installed in this container. Otherwise it starts `cloud-install.sh` in the
   background and returns at once.
2. `cloud-install.sh` downloads the `ak` 3.0.0 Linux binary from releases.agentkit.best,
   checks its SHA-256 against the pin in the official installer, logs in with
   `ak login --api-key-stdin`, and runs `ak kit init engineer --global` into the
   container's `~/.claude`. Log: `~/.agentkit-cloud-install.log`.
3. By default the kit's global hooks and status line are removed again after the install:
   they are written for the Mac, and some of them block or rewrite tool calls. Set
   `AGENTKIT_CLOUD_HOOKS=1` to keep them.

## Setup

1. Create an API key at agentkit.best (account page).
2. In the project's cloud environment settings, add the variable `AGENTKIT_API_KEY`.
3. Register the hook in `.claude/settings.json` under `hooks.SessionStart[0].hooks`:

   ```json
   { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/agentkit_cloud.sh\"", "timeout": 10 }
   ```

The install takes about a minute after the session starts; the `/ak:*` skills appear once it
finishes. To bump the version, copy the new stable `linux/amd64` and `linux/arm64` pins from
https://releases.agentkit.best/install.sh into `cloud-install.sh`.
