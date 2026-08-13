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
# Two hard safety rules, because this hook can block a session from ending:
#
#   1. stop_hook_active. Claude Code delivers a JSON payload on stdin whose
#      "stop_hook_active" field is true when a Stop hook has ALREADY blocked
#      in this stop sequence. Re-blocking then is how a Stop hook wedges a
#      session into a loop (Claude Code force-overrides after 8 consecutive
#      blocks, but only after 8 wasted turns). We exit 0 immediately in that
#      case: whatever we would have reported, we already reported once.
#   2. Bounded probe. The poll is a network call. A command hook's default
#      timeout is 600s, which is far too long to make a user wait to end a
#      session, so hooks.json pins a short "timeout" AND we wrap the poll in
#      an in-script watchdog (portable: macOS has no timeout(1)). A probe
#      that cannot answer quickly is treated as "nothing pending" — failing
#      open, because a missed notification costs one turn of latency while a
#      wedged session costs the whole session.
#
# Deliberate substitution from the build spec: spec §6 names a proposed
# "check_swarm_inbox" tool on the "rensei" HTTP MCP server as the follow-up
# the reason should point at. That tool does not exist and adding one is
# platform-side, out of REN-2352's scope ("reuses P2.2's existing tools,
# doesn't reimplement them"). The REAL, already-shipped equivalent is
# a2a_inbox on the same server — this hook's reason names that instead.
set -euo pipefail

PROBE_TIMEOUT_SECONDS="${RENSEI_STOP_PROBE_TIMEOUT:-8}"

# --- Rule 1: never block twice in the same stop sequence. -------------------
# Read the hook payload from stdin. No jq dependency: a substring match on the
# raw JSON is enough for a single boolean, and this hook must not fail just
# because jq is not installed.
# Guard the read: if stdin is a terminal there is no payload coming and a
# bare `cat` would block until the hook timeout.
INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat 2>/dev/null || true)"
fi
case "$INPUT" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*)
    exit 0
    ;;
esac

if ! command -v rensei >/dev/null 2>&1; then
  exit 0 # nothing to probe; do not block a session that lacks the CLI.
fi

# --- Rule 2: bounded probe. -------------------------------------------------
# Run the poll in the background and give it PROBE_TIMEOUT_SECONDS to finish.
# Portable across macOS (no coreutils timeout) and Linux.
TMP_OUT="$(mktemp -t rensei-stop-drain.XXXXXX)"
cleanup() { rm -f "$TMP_OUT"; }
trap cleanup EXIT

rensei channel poll-inbox >"$TMP_OUT" 2>/dev/null &
PROBE_PID=$!

waited=0
while kill -0 "$PROBE_PID" 2>/dev/null; do
  if [ "$waited" -ge "$PROBE_TIMEOUT_SECONDS" ]; then
    # Braces + redirect suppress the shell's own "Terminated" job notice,
    # which would otherwise land on this hook's stderr.
    {
      kill -TERM "$PROBE_PID" 2>/dev/null || true
      sleep 1
      kill -KILL "$PROBE_PID" 2>/dev/null || true
      wait "$PROBE_PID" || true
    } 2>/dev/null
    exit 0 # probe timed out — fail open, never wedge the stop.
  fi
  sleep 1
  waited=$((waited + 1))
done
wait "$PROBE_PID" 2>/dev/null || true

OUTPUT="$(cat "$TMP_OUT")"
if [ -n "$OUTPUT" ]; then
  echo "$OUTPUT"
  {
    echo "swarm events pending — the events above just arrived. Call the"
    echo "\"rensei\" MCP server's mcp__plugin_rensei_rensei__a2a_inbox tool for"
    echo "full structured detail (and the \"rensei-events\" server's"
    echo "mcp__plugin_rensei_rensei-events__ack_event /"
    echo "mcp__plugin_rensei_rensei-events__mark_handled once handled),"
    echo "then continue."
  } >&2
  exit 2
fi
exit 0
