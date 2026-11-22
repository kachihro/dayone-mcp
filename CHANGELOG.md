# Changelog

All notable changes to this project are listed here. Versions follow [semantic versioning](https://semver.org).

## [1.0.0] - 22/11/2026

First public release. 🎉

### Ways to use it
- **Claude Code plugin**: `/plugin install dayone --marketplace kachihro/dayone-mcp`. It adds
  `/dayone:on-this-day`, `/dayone:search`, `/dayone:reflect` and `/dayone:setup`, plus a skill that
  teaches Claude how to search a journal well. The plugin downloads its server on first use and
  checks it against the release's SHA-256 checksums.
- **MCP server** for Claude Desktop, VS Code (GitHub Copilot), Cursor and other MCP apps:
  self-contained builds for Windows x64, macOS (Apple silicon and Intel) and Linux (x64 and arm64).
- **Claude Desktop extension** (`.mcpb`) for Windows: double-click to install.
- **One-line installers**: `install.ps1` (Windows) and `install.sh` (macOS/Linux) set up Node.js, the
  Day One CLI, sign-in and sync, the server, the Claude Code plugin and Claude Desktop. Run again
  to update, or pass `-Uninstall` / `--uninstall` to remove.

### Tools
- `search_entries`, `on_this_day`, `list_journals`, `list_entries`, `read_entry`, `sync_journals`.
- Read-only: there are no tools to create, change or delete entries.
- Built on the official Day One CLI (`@dayone/cli`), with its optional telemetry turned off.
