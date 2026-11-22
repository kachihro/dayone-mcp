#!/usr/bin/env bash
# Day One MCP: sign in, add your encryption key, switch account or re-sync, without reinstalling.
#
#   curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/configure.sh | bash
#
# Runs install.sh --configure: the installer next to this file if there is one, otherwise the latest from GitHub.
set -euo pipefail
here=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
if [ -n "$here" ] && [ -f "$here/install.sh" ]; then
  exec bash "$here/install.sh" --configure "$@"
fi
url="${DAYONE_MCP_INSTALLER_URL:-https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh}"   # for forks and testing
curl -fsSL "$url" | bash -s -- --configure "$@"
