#!/usr/bin/env bash
# rensei-mcp-headers.sh — the "rensei" MCP server's headersHelper.
#
# Claude Code runs this fresh on every connection attempt to the "rensei"
# HTTP MCP server, and again on a 401/403 tool result before retrying once
# (see .mcp.json). Its entire job is printing a JSON object of headers to
# stdout — `rensei auth mcp-headers` already does exactly that, minting a
# fresh bearer token from the CLI's own token store (refreshing a near-expiry
# user token first). Nothing else belongs in this script: no caching, no
# retry loop — Claude Code owns the retry-on-401 behavior.
set -euo pipefail

if ! command -v rensei >/dev/null 2>&1; then
  echo "rensei CLI not found on PATH — install it (brew install RenseiAI/tap/rensei)" >&2
  echo "or switch the plugin's \"rensei\" MCP server entry to the api_token fallback" >&2
  echo "described in the plugin README." >&2
  exit 1
fi

exec rensei auth mcp-headers
