#!/usr/bin/env bash
# Day One MCP: remove it, and optionally sign out and remove the Day One CLI for a fresh start.
#
#   curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/uninstall.sh | bash
#
# Runs install.sh --uninstall: the installer next to this file if there is one, otherwise the latest from GitHub.
set -euo pipefail
here=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
if [ -n "$here" ] && [ -f "$here/install.sh" ]; then
  exec bash "$here/install.sh" --uninstall "$@"
fi
url="${DAYONE_MCP_INSTALLER_URL:-https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh}"   # for forks and testing
curl -fsSL "$url" | bash -s -- --uninstall "$@"
