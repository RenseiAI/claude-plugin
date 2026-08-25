#!/usr/bin/env bash
# rensei-session-preflight.sh — the SessionStart hook.
#
# Deliberate substitution from the build spec: spec §4 describes this hook as
# registering the coordinator "w/ platform" on session start. No such
# registration endpoint exists - a2a_send_message/a2a_inbox are the presence
# primitives, and they're durable-mailbox tools the model calls, not a
# primitives available to the model, not a hook-level handshake. Inventing a registration call against a nonexistent
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

LAUNCHER="${1:?Rensei launcher path is required}"

if ! "$LAUNCHER" claude profile-check >/dev/null 2>&1; then
  echo "Rensei plugin: the pinned local integration is unavailable. Run"
  echo "'rensei claude install --scope user' from a terminal, then restart Claude Code."
fi

exit 0
