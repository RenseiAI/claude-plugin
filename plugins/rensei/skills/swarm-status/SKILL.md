---
name: rensei:swarm-status
description: Roll up everything this coordinator has spawned — lineage, cost, and which children are stuck — without replaying every child's transcript by hand. Use this for a status check across multiple children, or when fallback-rung delivery might have been missed.
---

# Swarm status roll-up

Use this when you've lost track of what's running, want a cost/lineage
summary, or suspect a fallback-rung event (see `rensei:setup`) might have
been dropped — channel notifications have no transport ack (spec: they can
be silently dropped if the session wasn't opted into `--channels` or org
policy blocks it), so treat this roll-up as the durable source of truth, not
the notification stream.

## Building the roll-up

Tool names below are shortened for reading — call them with their full
prefix: `mcp__plugin_rensei_rensei__<tool>` for everything on the HTTP
server, and `mcp__plugin_rensei_rensei-events__<tool>` for
`ack_event`/`mark_handled`.

1. `a2a_list_agents` — every peer addressable in this project, with
   `presence` (durable delivery works regardless of whether a peer is
   currently running; presence just tells you whether it's live right now).
2. For each session id you've dispatched (or that showed up in
   `a2a_list_agents` with a lineage pointing back to you): `get_session_receipt`
   for anything reported done, `watch_session` for anything still running you
   want a live read on.
3. `a2a_inbox` — check for any durable messages that arrived but were never
   acted on (a `msg_id` you never called `ack_event`/`mark_handled` for is
   exactly the "did I miss a fallback-rung delivery" signal).

## Reading the result

- **Stuck**: dispatched, no receipt, no recent transcript activity via
  `watch_session`, and no pending inbox message from it either. Candidate
  for `cancel_session` or `steer_child` with a nudge, not silent write-off —
  a child that's actually still working looks identical from the outside
  until you check.
- **Lineage**: `spawn_depth` on each session tells you how far from you it
  is (a child of a child you spawned is depth 2, etc.) — the platform
  enforces a depth cap, so a lineage chain approaching it is worth flagging
  before you spawn further from that branch.
- **Cost**: receipts carry cost; a subtree total is the sum across every
  receipt under one root session id, not a separate tool call.

Do not treat a child's own status claims in free-text as the roll-up's
source of truth — reconcile against `get_session_receipt`'s typed fields
and `watch_session`'s actual transcript, the same untrusted-content
discipline as `rensei:delegate` and the `swarm-triage` agent.
