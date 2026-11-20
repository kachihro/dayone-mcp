# Changelog

## [1.0.0] - 19/11/2026

First public release. 🎉

- Read-only MCP server for Day One, built on the official Day One CLI (`@dayone/cli`).
- Tools: `search_entries`, `on_this_day`, `list_journals`, `list_entries`, `read_entry`, `sync_journals`.
- One-line installers for Windows (`install.ps1`) and macOS/Linux (`install.sh`) that set up Node.js,
  the Day One CLI, the server, Claude Code and Claude Desktop.
- Claude Desktop extension (`.mcpb`) for Windows, with its own icon.
- Claude Code plugin and marketplace (`/plugin install dayone --marketplace kachihro/dayone-mcp`) with
  `/dayone:on-this-day`, `/dayone:search`, `/dayone:reflect` and `/dayone:setup`, plus a skill that teaches
  Claude how to search a journal well. The plugin downloads its server on first use and checks it
  against the release's SHA-256 checksums. The one-line installers use the plugin for Claude Code.
- Self-contained builds for Windows x64, macOS (Apple silicon and Intel) and Linux (x64 and arm64).
