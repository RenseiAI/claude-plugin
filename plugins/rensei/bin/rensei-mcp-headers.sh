#!/usr/bin/env bash
# Claude Code reruns headersHelper at connect and reconnect. The Rensei CLI
# validates Claude's actual endpoint against the installed profile before it
# resolves the pinned user credential, then emits auth + tenant scope together.
set -euo pipefail

LAUNCHER="${1:?Rensei launcher path is required}"
exec "$LAUNCHER" claude mcp-headers
