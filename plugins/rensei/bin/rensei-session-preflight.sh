#!/usr/bin/env bash
# rensei-session-preflight.sh — the SessionStart hook.
#
# Deliberate substitution from the build spec: spec §4 describes this hook as
# registering the coordinator "w/ platform" on session start. No such
# registration endpoint exists — a2a_send_message/a2a_inbox (verified real,
# platform/src/lib/mcp/tool-names.ts) are the only confirmed presence
# primitives, and they're durable-mailbox tools the model calls, not a
# hook-level handshake. Inventing a registration call against a nonexistent
# endpoint would be worse than not having one, so this hook instead does the
# one thing that IS real and checkable from a shell script: confirm the
# rensei CLI is present and authenticated, and say so plainly when it isn't,
# pointing at the /rensei:setup skill rather than silently degrading.
#
# Output goes to STDOUT, not stderr. For a SessionStart hook exiting 0,
# stdout is what Claude Code adds to the session context — which is exactly
# where a "your swarm tools will not work and here is why" notice needs to
# land, so the model can surface it and act on it. Hook stderr on a success
# exit is not reliably shown to anyone. Nothing is printed on the happy path,
# so this costs zero context in a healthy install.
#
# This hook must stay cheap: it runs on every single session start. Both
# checks below are local-only (PATH lookup + the CLI's own token store); no
# network call. Measured ~55ms on a healthy install. hooks.json also pins a
# short timeout so a pathological install cannot stall session startup.
set -euo pipefail

if ! command -v rensei >/dev/null 2>&1; then
  echo "Rensei plugin: the \"rensei\" CLI is not on PATH. Spawn/steer tools and the"
  echo "channel/monitor fallbacks will not work until it is installed. Run the"
  echo "/rensei:setup skill, or: brew install RenseiAI/tap/rensei && rensei auth add --user"
  echo "(If rensei IS installed, Claude Code may have been launched without your"
  echo "shell profile — see the plugin README's \"rensei not found\" troubleshooting.)"
  exit 0 # advisory only — never blocks session start.
fi

if ! rensei auth mcp-headers >/dev/null 2>&1; then
  echo "Rensei plugin: the rensei CLI is installed but not authenticated. Run"
  echo "/rensei:setup or 'rensei auth add --user' to enable the swarm tools."
fi

exit 0
