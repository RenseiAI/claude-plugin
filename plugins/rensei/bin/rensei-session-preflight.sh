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
set -euo pipefail

if ! command -v rensei >/dev/null 2>&1; then
  echo "Rensei plugin: the \"rensei\" CLI is not on PATH. Spawn/steer tools and the" >&2
  echo "channel/monitor fallbacks will not work until it is installed. Run the" >&2
  echo "/rensei:setup skill, or: brew install RenseiAI/tap/rensei && rensei auth add --user" >&2
  exit 0 # advisory only — never blocks session start.
fi

if ! rensei auth mcp-headers >/dev/null 2>&1; then
  echo "Rensei plugin: the rensei CLI is installed but not authenticated. Run" >&2
  echo "/rensei:setup or 'rensei auth add --user' to enable the swarm tools." >&2
fi

exit 0
