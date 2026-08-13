#!/usr/bin/env bash
# rensei-stop-drain-check.sh — the Stop hook (fallback ladder rung 3).
#
# Rung 3 exists so the coordinator never idles past a swarm event on installs
# where neither the channel (rung 1, preview-gated) nor the monitor (rung 2)
# is running. Every turn boundary, this hook does a fast inbox probe: if
# anything new landed, it blocks the stop (exit 2) with a reason on stderr so
# Claude reads it before actually ending the turn — the documented Claude
# Code Stop-hook contract (block-with-reason via a non-zero exit + stderr).
#
# It reuses "rensei channel poll-inbox" (same cursor file the swarm-inbox
# monitor uses, in ~/.rensei/channel-inbox-cursor.json) rather than a
# separate probe — whichever rung's poll fires first advances the shared
# cursor, so this hook and the monitor never double-report the same event.
#
# Deliberate substitution from the build spec: spec §6 names a proposed
# "check_swarm_inbox" tool on the "rensei" HTTP MCP server as the follow-up
# the reason should point at. That tool does not exist and adding one is
# platform-side, out of REN-2352's scope ("reuses P2.2's existing tools,
# doesn't reimplement them"). The REAL, already-shipped equivalent is
# a2a_inbox on the same server — this hook's reason names that instead.
set -euo pipefail

if ! command -v rensei >/dev/null 2>&1; then
  exit 0 # nothing to probe; do not block a session that lacks the CLI.
fi

OUTPUT="$(rensei channel poll-inbox 2>/dev/null || true)"
if [ -n "$OUTPUT" ]; then
  echo "$OUTPUT"
  {
    echo "swarm events pending — the events above just arrived. Call the"
    echo "\"rensei\" MCP server's a2a_inbox tool for full structured detail"
    echo "(and ack_event/mark_handled on \"rensei-events\" once handled),"
    echo "then continue."
  } >&2
  exit 2
fi
exit 0
