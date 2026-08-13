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
# channel_cmd.go). This script only adds the "loop forever", the failure
# reporting, and the double-delivery guard below.
#
# STDOUT IS THE ONLY CHANNEL THAT REACHES ANYONE. Claude Code turns each
# stdout line into a notification and DISCARDS a monitor's stderr entirely.
# It also does not restart a monitor that exits — one exit and rung 2 is dead
# for the rest of the session. So every condition a human needs to know about
# (missing CLI, a persistently failing poll) must be announced on stdout
# before we exit or settle into a retry loop, and routine per-cycle noise must
# stay OFF stdout so it doesn't spam the notification stream.
#
# Double-delivery guard (opt-in — see RENSEI_MONITOR_RESPECT_CHANNEL below):
# if "rensei channel serve" (rung 1) is ALSO running and its channel actually
# registered, both rungs would deliver the same events. "rensei channel serve"
# touches a heartbeat file (~/.rensei/channel-active.flag) after every
# successful poll tick. But that heartbeat proves only that the rung-1 poll
# loop is ALIVE, not that any notification it sent was ever DELIVERED — and
# Claude Code spawns "rensei channel serve" as the "rensei-events" stdio
# server on every session regardless of whether --channels was passed. So on
# a default install (no --channels, the mode the README says most people run)
# the heartbeat is fresh while rung 1 delivers nothing, and honoring it would
# suppress rung 2 permanently — losing rungs 1 AND 2 together and leaving
# only the Stop hook.
#
# The asymmetry decides it: honoring a stale-but-live heartbeat costs a LOST
# delivery path; ignoring a genuinely-live channel costs a DUPLICATE
# notification, which skills already dedupe by msg_id. So the guard is
# off by default — set RENSEI_MONITOR_RESPECT_CHANNEL=1 to re-enable it if
# you actually run with --channels and would rather not see duplicates.
# (CLI-side follow-up: make the heartbeat record channel REGISTRATION rather
# than poll liveness, and this can safely go back to being the default.)
set -euo pipefail

POLL_INTERVAL_SECONDS="${RENSEI_MONITOR_POLL_INTERVAL:-15}"
RESPECT_CHANNEL="${RENSEI_MONITOR_RESPECT_CHANNEL:-0}"
HEARTBEAT_FLAG="${HOME}/.rensei/channel-active.flag"

# How many consecutive failed polls before we say so on stdout (once), and
# how much we stretch the interval while failing, so a hard outage (expired
# credential, platform 403) degrades to a slow retry instead of a hot loop.
FAILURE_NOTICE_AFTER="${RENSEI_MONITOR_FAILURE_NOTICE_AFTER:-4}"
MAX_BACKOFF_SECONDS="${RENSEI_MONITOR_MAX_BACKOFF:-300}"

if ! command -v rensei >/dev/null 2>&1; then
  # stdout, not stderr: a monitor's stderr is discarded, and this is the one
  # message that explains why rung 2 is about to be dead for the session.
  echo "rensei-inbox-follow: the rensei CLI is not on PATH, so swarm-event polling (fallback rung 2) is off for this session — install it with 'brew install RenseiAI/tap/rensei' and restart Claude Code."
  exit 1
fi

heartbeat_is_fresh() {
  # Fresh = modified within the last minute. find's -mmin is the one mtime-age
  # check both BSD (macOS) and GNU find support identically.
  [ -f "$HEARTBEAT_FLAG" ] && [ -n "$(find "$HEARTBEAT_FLAG" -mmin -1 2>/dev/null)" ]
}

consecutive_failures=0
notified_failure=0

while true; do
  sleep_for="$POLL_INTERVAL_SECONDS"

  if [ "$RESPECT_CHANNEL" = "1" ] && heartbeat_is_fresh; then
    : # channel rung appears live this cycle — skip the redundant poll.
  elif rensei channel poll-inbox 2>/dev/null; then
    if [ "$notified_failure" = "1" ]; then
      echo "rensei-inbox-follow: swarm-event polling recovered."
    fi
    consecutive_failures=0
    notified_failure=0
  else
    consecutive_failures=$((consecutive_failures + 1))
    if [ "$consecutive_failures" -ge "$FAILURE_NOTICE_AFTER" ] && [ "$notified_failure" = "0" ]; then
      echo "rensei-inbox-follow: swarm-event polling has failed ${consecutive_failures} times in a row (fallback rung 2 is not delivering). Run 'rensei channel poll-inbox' by hand to see the error — usually authentication ('rensei auth add --user') or a platform-side outage. Retrying with backoff."
      notified_failure=1
    fi
    # Linear backoff, capped, while we are failing.
    sleep_for=$((POLL_INTERVAL_SECONDS * consecutive_failures))
    [ "$sleep_for" -gt "$MAX_BACKOFF_SECONDS" ] && sleep_for="$MAX_BACKOFF_SECONDS"
  fi

  sleep "$sleep_for"
done
