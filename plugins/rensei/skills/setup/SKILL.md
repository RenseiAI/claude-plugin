---
name: rensei:setup
description: Check the Rensei CLI is installed and authenticated, verify the MCP tool surface, and explain the channel/monitor/hook fallback ladder for this install. Run this first, and any time swarm tools seem unavailable.
---

# Rensei setup

Use this skill before spawning or steering anything with Rensei, and any time
a `mcp__plugin_rensei_rensei__*` tool call fails outright (connection error,
not a domain error from the tool itself).

## 1. Confirm the CLI

```bash
rensei claude status
```

- Not installed: `brew install RenseiAI/tap/rensei`, then `rensei auth add --user`.
- Not ready: select the intended org/project and run `rensei claude install --scope user`.

The plugin's `.mcp.json` server uses the metadata-only profile created by the
installer. The helper re-runs on every connection/reconnect, refreshes the
pinned user credential, validates the platform origin, and sends the pinned
org/project headers. Active CLI context changes do not rescope this session.

## 2. Know which fallback rung you're on

The plugin delivers swarm events (a child completing, blocking, or needing
input) on one of four rungs, automatically, cheapest-working-one-first:

| Rung | What | Needs |
| --- | --- | --- |
| 1. Channel | Live push into your turn, plus remote tool-approval relay | Claude Code launched with `--channels plugin:rensei@rensei` (or `--dangerously-load-development-channels`), AND your org's `channelsEnabled`/`allowedChannelPlugins` managed settings allow it (Team/Enterprise) or you're on an individual Pro/Max/Console plan (no org gate there) |
| 2. Monitor | A background poll loop prints one line per new event | Nothing — sanctioned, flag-free, on by default |
| 3. Stop hook | End-of-turn probe blocks with a reason if events are pending | Nothing — on by default |
| 4. Durable poll | Call `a2a_inbox` yourself, or run `/rensei:swarm-status` | Always available |

Rungs 2–4 need no flags and work today. Rung 1 is a Claude Code **research
preview** with an allowlist a third-party plugin cannot self-serve onto — see
the plugin README's "Channel allowlist" section before assuming `--channels`
will work for you. If you never pass `--channels`, you are running rungs
2–4 only, and that is a fully supported, non-degraded mode — not a
consolation prize.

## 3. Verify the tool surface

Call `mcp__plugin_rensei_rensei__a2a_list_agents` (no args). An empty or
populated list back means the "rensei" server is reachable and authenticated.
If it errors, re-run step 1.

Every tool this plugin provides is namespaced — use the full names:
`mcp__plugin_rensei_rensei__<tool>` for the HTTP server below, and
`mcp__plugin_rensei_rensei-events__<tool>` for `ack_event`/`mark_handled` on
the stdio channel server. A bare `a2a_inbox` or `ack_event` is not a tool
name and will not resolve.

The typed spawn/steer/observe tools (`dispatch_child`, `steer_child`,
`watch_session`, `replay_session`, `cancel_session`, `get_session_receipt`)
require your credential to carry the platform's spawn capability
(`interactive_agent_spawn`, informally "the `spawn:invoke` scope"). If a call
to one of them fails specifically with an authorization/capability error
(not a connection error), that credential does not have it yet — this is an
org-side grant, not something this skill can fix locally.

See the `rensei:swarm` skill for spawn/steer patterns once setup checks out.
