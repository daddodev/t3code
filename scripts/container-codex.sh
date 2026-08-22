#!/bin/sh
set -eu

# Desktop keyrings are unavailable or ephemeral in most containers. Keep MCP
# OAuth credentials beside the rest of the mounted Codex state instead.
exec /usr/local/bin/codex-cli -c 'mcp_oauth_credentials_store="file"' "$@"
