#!/usr/bin/env bash
# rensei-inbox-follow.sh — the "swarm-inbox" monitor (fallback ladder rung 2).
#
# A monitor is a persistent background command Claude Code starts once and
# keeps reading: every stdout line becomes a notification, no --channels flag
# and no channels-preview allowlist required (see monitors/monitors.json and
# the plugin README's allowlist caveat). This script is the sanctioned,
# flag-free push path for installs that can't or don't run the channel rung.
#
# It loops `rensei channel poll-inbox` on an interval and prints whatever new
# lines it returns — that subcommand already does the actual a2a_inbox poll +
# cursor persistence (internal/channel.PollInboxLines, cmd/rensei/
# channel_cmd.go). This script only adds the "loop forever" and the
# double-delivery guard below.
#
# Double-delivery guard: if "rensei channel serve" (rung 1) is ALSO running
# and its channel actually registered, both rungs would otherwise deliver the
# same events. "rensei channel serve" touches a heartbeat file
# (~/.rensei/channel-active.flag) after every successful poll tick — best
# effort only; per the build spec (§6) there is no documented API that tells
# a server whether Claude Code actually registered it as a channel, so a
# fresh heartbeat proves the poll loop is alive, not that any notification it
# sent was ever delivered. When the heartbeat looks fresh we skip polling
# this cycle; skills still dedupe by msg_id regardless, so a missed guard
# (heartbeat stale but the channel is in fact live) costs a duplicate
# notification, never a lost one.
set -euo pipefail

POLL_INTERVAL_SECONDS="${RENSEI_MONITOR_POLL_INTERVAL:-15}"
HEARTBEAT_FLAG="${HOME}/.rensei/channel-active.flag"

if ! command -v rensei >/dev/null 2>&1; then
  echo "rensei-inbox-follow: rensei CLI not found on PATH — install it (brew install RenseiAI/tap/rensei)" >&2
  exit 1
fi

heartbeat_is_fresh() {
  # Fresh = modified within the last minute. find's -mmin is the one mtime-age
  # check both BSD (macOS) and GNU find support identically.
  [ -f "$HEARTBEAT_FLAG" ] && [ -n "$(find "$HEARTBEAT_FLAG" -mmin -1 2>/dev/null)" ]
}

while true; do
  if heartbeat_is_fresh; then
    : # channel rung appears live this cycle — skip the redundant poll.
  else
    rensei channel poll-inbox || echo "rensei-inbox-follow: poll-inbox failed (will retry next cycle)" >&2
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done
