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
#
# RENSEI_API_TOKEN fallback. For machines where the CLI genuinely cannot be
# installed, a raw platform token in $RENSEI_API_TOKEN is used when the CLI
# is missing or cannot produce headers. This is the ONLY mechanical path for
# a static token: Claude Code rejects ${user_config.*} inside a headersHelper
# (the value would be passed to a shell), so a plugin.json userConfig entry
# cannot reach this script — the env var is the supported substitute. Set it
# in your shell profile, or in settings.json under "env". It does not refresh,
# so prefer the CLI path whenever it is available.
set -euo pipefail

emit_env_token() {
  if [ -n "${RENSEI_API_TOKEN:-}" ]; then
    printf '{"Authorization":"Bearer %s"}\n' "$RENSEI_API_TOKEN"
    return 0
  fi
  return 1
}

if ! command -v rensei >/dev/null 2>&1; then
  if emit_env_token; then
    exit 0
  fi
  echo "rensei CLI not found on PATH — install it (brew install RenseiAI/tap/rensei)" >&2
  echo "or export RENSEI_API_TOKEN=rsk_... to use the static-token fallback" >&2
  echo "described in the plugin README." >&2
  exit 1
fi

# The CLI is present. Prefer it, but fall back to the env token if it cannot
# produce headers (no auth context active) rather than failing the connection
# outright when the operator has supplied a token by hand.
if HEADERS="$(rensei auth mcp-headers 2>/dev/null)" && [ -n "$HEADERS" ]; then
  printf '%s\n' "$HEADERS"
  exit 0
fi

if emit_env_token; then
  exit 0
fi

echo "rensei CLI is installed but has no active auth context — run" >&2
echo "'rensei auth add --user', or export RENSEI_API_TOKEN=rsk_... to use the" >&2
echo "static-token fallback described in the plugin README." >&2
exit 1
