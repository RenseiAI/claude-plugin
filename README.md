# Rensei Claude Code plugin marketplace

Marketplace repo for the Rensei Claude Code plugin (extracted from
`rensei-tui/plugin/claude/` per its staging note; canonical here as of
2026-08-13).

Install:

```bash
brew install RenseiAI/tap/rensei
rensei auth add --user
rensei claude install --scope user
```

```
.claude-plugin/marketplace.json   marketplace manifest ("rensei")
plugins/rensei/                   the plugin itself
```

The Rensei CLI registers this public marketplace, installs the plugin, and
pins the selected user identity, platform origin, organization, and optional
project. See `plugins/rensei/README.md` for the fallback ladder and channel
allowlist caveat.
