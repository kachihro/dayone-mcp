# Changelog

All notable changes to this project are listed here. Versions follow [semantic versioning](https://semver.org).

## [1.0.1] - 22/11/2026

Easier, friendlier installers. The MCP server itself is unchanged.

### Installers
- macOS/Linux installer brought up to date with Windows: two parts, `configure.sh` and
  `uninstall.sh`, a password prompt that shows `*` and accepts pasting, encrypted-journal detection
  with the Mac key steps, a full-reset uninstall and emoji output (plain text in non-UTF-8 terminals).
  Works with the bash 3.2 that macOS uses for `curl | bash`.
- Live sync progress on both platforms: a spinner with the journal number and entry count, then
  "Synced 1,480 entries".
- README: new "Using it in Claude Code" section.
- The closing "Buy me a coffee" line uses 💜 and a clickable link (OSC 8 terminal hyperlink, with the
  full https:// address as text so other terminals can still detect it).

### Windows installer
- Easier Day One sign-in: the password and encryption key prompts show `*` and accept pasting, and
  are passed to the Day One CLI without appearing on screen or in history.
- Shows just the key details (who signed in, plan, journal names) instead of the full account record.
- Only asks for the encryption key if the account uses end-to-end encryption.
- Shorter output with emoji in Windows Terminal, PowerShell 7 and VS Code (plain text elsewhere).
- Fixed garbled characters from Claude Code's output, and no longer tries to sync after a failed sign-in.
- New `uninstall.ps1`: removes Day One MCP, then optionally signs out and removes the Day One CLI and
  its downloaded journals for a fresh start (asks first; defaults to no).
- New `configure.ps1`: sign in, add your encryption key, switch account or re-sync, without reinstalling.
- The installer now runs in two parts: "Adding Day One MCP" then "Setting it up for you".
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
