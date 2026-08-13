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
command -v rensei || echo "not installed"
rensei auth mcp-headers >/dev/null 2>&1 && echo "authenticated" || echo "not authenticated"
```

- Not installed: `brew install RenseiAI/tap/rensei`, then `rensei auth add --user`.
- Not authenticated: `rensei auth add --user` (opens a browser device-auth flow).

The plugin's `.mcp.json` "rensei" server uses `rensei auth mcp-headers` as its
`headersHelper` — it re-runs automatically on every connection and on a
401/403, so once authenticated here you should not need to touch it again.

If the CLI genuinely cannot be installed on this machine, export a raw
platform token as `RENSEI_API_TOKEN` (in your shell profile, or under `"env"`
in `settings.json`) — the `headersHelper` script uses it whenever the CLI is
missing or has no active auth context. Do not edit the plugin's `.mcp.json`
to do this: it lives in the plugin cache and is overwritten on every update.
Prefer the CLI path regardless; a static token does not refresh.

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
