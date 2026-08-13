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

> **Staging note**: this plugin currently lives inside the closed-source
> `rensei-tui` repo at `plugin/claude/` rather than its own
> `RenseiAI/claude-plugin` repo (the marketplace path above assumes that
> repo exists). Extracting it there — so `/plugin marketplace add` works
> against a real repo, and so the plugin's contents can be public even
> though `rensei-tui`'s source is not — is follow-up work, not part of
> REN-2352. Until then, install for local development instead:
> `claude --plugin-dir /path/to/rensei-tui/plugin/claude/plugins/rensei`.

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

Rung selection is automatic and best-effort: `rensei channel serve` writes a
heartbeat file after each poll tick; the monitor skips its own poll when that
heartbeat looks fresh, to avoid double-delivering the same event. Every event
carries a `msg_id` regardless of which rung delivered it — skills dedupe on
it, so an imperfect rung-selection guess costs at most a duplicate
notification, never a lost one.

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

## Troubleshooting

- **`rensei` not found**: the `SessionStart` hook and `headersHelper` both
  degrade to a clear stderr message rather than failing silently — read it.
- **MCP tools connect but every call errors**: run `rensei auth mcp-headers`
  by hand; a non-zero exit means you're not authenticated (`rensei auth add
  --user`).
- **No channel push, ever**: expected unless you did one of the two allowlist
  things above. Confirm the monitor is running instead (`/status` should list
  the "swarm-inbox" monitor) — that's rung 2, and it's what most installs run
  on.
- **Duplicate notifications for the same event**: dedupe by `msg_id` — this
  can happen when rung 3 (Stop hook) and rung 2 (monitor) both fire close
  together before the shared cursor file catches up; it is a documented,
  tolerated failure mode (spec §6), not a bug report.
