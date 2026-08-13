# Rensei Claude Code plugin

Spawn, steer, and hear back from Rensei-hosted sub-agents from inside a
Claude Code session — the swarm coordinator front-end for Claude
(REN-2352, design `06-design.md` §3.3). Built against the verified channel
and plugin contract in `runs/2026-08-12-coordinator-swarm/research/
ren-2351-claude-plugin-spec.md`.

## What's in here

| Piece | What it does |
| --- | --- |
| `rensei` MCP server (`.mcp.json`) | Remote HTTP MCP over `/api/cli/mcp`: spawn/steer/observe tools (`dispatch_child`, `steer_child`, `watch_session`, `replay_session`, `cancel_session`, `get_session_receipt`) plus the durable A2A mailbox (`a2a_list_agents`, `a2a_send_message`, `a2a_inbox`). Auth via `headersHelper` → `rensei auth mcp-headers`, re-minted fresh on every connection and on 401/403. |
| `rensei-events` MCP server (`.mcp.json`) | The stdio **channel**: `rensei channel serve` — pushes swarm events (child completed/blocked/needs-input) into your live session, relays tool-approval requests, and exposes `ack_event`/`mark_handled`. |
| Monitor (`monitors/monitors.json`) | `rensei-inbox-follow.sh` — flag-free fallback push: a background loop that prints one line per new event. |
| Hooks (`hooks/hooks.json`) | `SessionStart` preflight (CLI installed + authenticated); `Stop` drain-check (blocks end-of-turn with a reason if events are pending). |
| Skills (`skills/`) | `/rensei:setup`, `/rensei:swarm`, `/rensei:delegate`, `/rensei:swarm-status` — usage patterns for the tool vocabulary above. |
| Agent (`agents/swarm-triage.md`) | Read-only local subagent that summarizes a child's transcript/receipt with untrusted-content handling, so you don't have to hold a full transcript in your own context. |

## Install

Prerequisite: the `rensei` CLI, installed and authenticated.

```bash
brew install RenseiAI/tap/rensei
rensei auth add --user
```

Then, in Claude Code:

```
/plugin marketplace add RenseiAI/claude-plugin
/plugin install rensei@rensei
```

Choose **user** scope when prompted. If the install summary asks for it, run
`/reload-plugins`. Run `/rensei:setup` afterward to confirm the CLI and MCP
tool surface are both reachable.

> **`RenseiAI/claude-plugin` is a private repo.** `/plugin marketplace add`
> clones it with your local git credentials, so you need read access to that
> repo and a working `git`/`gh` credential for GitHub before the command
> above will succeed. If it fails with a clone/permission error, that is what
> it means — ask for repo access rather than re-running it.

To work on the plugin itself, point Claude Code at a checkout directly
instead of installing from the marketplace:

```bash
claude --plugin-dir /path/to/claude-plugin/plugins/rensei
```

## The channel allowlist caveat — read this before assuming push works

Claude Code **channels** (the live-push mechanism `rensei-events` uses) are a
**research preview** with an allowlist a third-party plugin cannot self-serve
onto. Concretely, as of 2026-08-12:

- The channel MCP server **always connects and its tools still work**
  regardless of allowlist status — only the live push notifications don't
  arrive. Nothing breaks; you just don't get rung 1.
- To actually get channel push, one of two things must be true:
  1. **Team/Enterprise org**: an Owner sets `channelsEnabled: true` and adds
     this plugin to `allowedChannelPlugins` in managed settings:
     ```json
     {
       "channelsEnabled": true,
       "allowedChannelPlugins": [{ "marketplace": "rensei", "plugin": "rensei" }]
     }
     ```
  2. **Anyone else**: launch with
     `claude --channels plugin:rensei@rensei --dangerously-load-development-channels`
     — a per-entry bypass behind a full-screen "I am using this for local
     development" warning dialog. There is no other self-serve path; the
     community marketplace is explicitly not on Anthropic's default
     allowlist, and official-listing is a partner-contact process, not an
     application.
  3. Either way, being listed in `.mcp.json` is **not enough** — the session
     must also be launched with `--channels plugin:rensei@rensei` (space-
     separated if combined with other channel plugins).
- **Pro/Max individual accounts have no org-level check at all** — only the
  `--channels`/dev-flag requirement above applies to you.

**You do not need any of this to get real value from the plugin.** The
monitor (rung 2) and Stop hook (rung 3) require no flags, run by default, and
degrade to nothing worse than "you find out at the next turn boundary
instead of mid-turn." Rung 1 is the fastest rung, not the only functional
one — see `/rensei:setup` for the full ladder.

## Fallback ladder

| Rung | Mechanism | Needs |
| --- | --- | --- |
| 1 | Channel push + permission relay | Allowlist/dev-flag above |
| 2 | Monitor (`rensei-inbox-follow.sh`) | Nothing |
| 3 | Stop hook drain-check | Nothing |
| 4 | Durable poll (`a2a_inbox`, or `/rensei:swarm-status`) | MCP reachability only |

Rungs 2 and 3 both run by default and both poll the same durable inbox, so
the same event can surface twice. That is deliberate. Every event carries a
`msg_id` regardless of which rung delivered it and the skills dedupe on it,
so a duplicate costs nothing — whereas suppressing a rung costs a delivery
path.

`rensei channel serve` does write a heartbeat file after each poll tick, and
the monitor *can* skip its own poll while that heartbeat is fresh — but this
is **off by default**, because Claude Code starts `rensei channel serve` as
the `rensei-events` MCP server on every session whether or not `--channels`
was passed. On a default install the heartbeat is therefore fresh while rung
1 delivers nothing, and honoring it would silently disable rung 2 as well.
If you actually run with `--channels` and would rather not see duplicates,
set `RENSEI_MONITOR_RESPECT_CHANNEL=1`.

## Honest status: what's real vs. what needs a live platform

Everything in this plugin — the MCP protocol handling, the `a2a_inbox`/
`a2a_send_message`/`a2a_complete_task` wire calls, the event mapping, the
permission-relay mechanics, `ack_event`/`mark_handled`, the redelivery sweep —
is implemented and covered by unit tests in `rensei-tui`'s `internal/channel`
package against fake MCP servers, because that's what's testable without a
deployed platform. What is NOT verified end-to-end against a live platform:

- Whether the typed `dispatch_child`/`steer_child`/`watch_session`/
  `replay_session`/`cancel_session`/`get_session_receipt` tools are live on
  your org's `/api/cli/mcp` yet — they require the platform-side capability
  handshake this plugin depends on but does not implement (P2.2/P4.1). If a
  call to one of them fails with a connection/handshake error rather than a
  normal tool error, check with your platform admin whether that rollout has
  landed; `a2a_list_agents`/`a2a_send_message`/`a2a_inbox` do not depend on it
  and should work regardless.
- The permission relay's `RequestApproval` posts to a placeholder a2a handle
  (`--permission-relay-recipient`, default `rensei-permission-relay`) — until
  something on the platform side actually reads that handle's mailbox and
  answers, every relayed approval request times out. This is expected, not a
  bug: there is no dedicated approval UX (dashboard/phone) shipped yet.

## Authentication

The `rensei` MCP server authenticates through its `headersHelper`, which
shells out to `rensei auth mcp-headers` — a fresh token per connection, and
again on a 401/403. `rensei auth add --user` is the whole setup.

If the CLI cannot be installed on a machine, export a raw platform token
instead and the helper will use it whenever the CLI is missing or has no
active auth context:

```bash
export RENSEI_API_TOKEN=rsk_...
```

(or set it under `"env"` in `settings.json`). A static token does not
refresh, so prefer the CLI path. Note there is deliberately **no**
`/plugin configure` option for this: Claude Code refuses `${user_config.*}`
inside a `headersHelper` because the value would be passed to a shell, so an
env var is the only mechanical path — a userConfig entry would have been a
knob wired to nothing. Do not hand-edit the plugin's `.mcp.json` either; it
lives in the plugin cache and is overwritten on every update.

## Troubleshooting

- **`rensei` not found — but it IS installed**: Claude Code inherits the
  environment it was launched from. Launched from a GUI (Dock, Spotlight) on
  macOS it may not see `/opt/homebrew/bin`, so a Homebrew-installed `rensei`
  is invisible to the `rensei-events` server, the hooks, and the monitor.
  Launch `claude` from a terminal, or add the directory to `PATH` in
  `settings.json` under `"env"`.
- **`rensei` genuinely not installed**: the `SessionStart` hook says so in
  session context and the monitor says so as a notification — read either.
- **MCP tools connect but every call errors**: run `rensei auth mcp-headers`
  by hand; a non-zero exit means you're not authenticated (`rensei auth add
  --user`). A `403` mentioning `Missing required scope` is platform-side, not
  a local misconfiguration.
- **No channel push, ever**: expected unless you did one of the two allowlist
  things above. Confirm the monitor is running instead (`/status` should list
  the "swarm-inbox" monitor) — that's rung 2, and it's what most installs run
  on.
- **Duplicate notifications for the same event**: dedupe by `msg_id` — this
  can happen when rung 3 (Stop hook) and rung 2 (monitor) both fire close
  together before the shared cursor file catches up; it is a documented,
  tolerated failure mode (spec §6), not a bug report.
