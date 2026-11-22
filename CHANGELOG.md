# Changelog

All notable changes to this project are listed here. Versions follow [semantic versioning](https://semver.org).

## Unreleased

### Windows installer
- Easier Day One sign-in: the password and encryption key prompts show `*` and accept pasting, and
  are passed to the Day One CLI without appearing on screen or in history.
- Shows just the key details (who signed in, plan, journal names) instead of the full account record.
- Only asks for the encryption key if the account uses end-to-end encryption.
- Shorter output with emoji in Windows Terminal, PowerShell 7 and VS Code (plain text elsewhere).
- Fixed garbled characters from Claude Code's output, and no longer tries to sync after a failed sign-in.
- Detects encrypted journals after syncing, shows 3 steps to find your key, and checks the key really
  unlocks your entries. Re-running the installer when already signed in goes straight to this check.

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
