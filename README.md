# Rensei Claude Code plugin marketplace

Marketplace repo for the Rensei Claude Code plugin (extracted from
`rensei-tui/plugin/claude/` per its staging note; canonical here as of
2026-08-13).

Install:

```
/plugin marketplace add RenseiAI/claude-plugin
/plugin install rensei@rensei
```

```
.claude-plugin/marketplace.json   marketplace manifest ("rensei")
plugins/rensei/                   the plugin itself
```

See `plugins/rensei/README.md` for what the plugin does, setup (prefer
`rensei auth add --user` over the api_token fallback), and the
channel-allowlist caveat.
