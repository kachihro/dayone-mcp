# Changelog

All notable changes to this project are listed here. Versions follow [semantic versioning](https://semver.org).

## [1.0.3] - 22/11/2026

Works with nvm, smoother updates and Claude Desktop restarts on Windows, one fewer installer question,
and a new, easier README.

### README and docs
- New, shorter README: one command to install, then read-only access to query your journals. Clear
  "How to use" for Claude Desktop and Claude Code, copyable commands, and FAQs.
- Pictures in kachihro branding with light and dark versions that match the reader's GitHub theme, and
  a new "How to use" picture.
- Advanced material moved to [Manual setup](docs/manual-setup.md) and [Troubleshooting](docs/troubleshooting.md).

### Installers
- **Windows: Claude Desktop now gets Day One as an extension**, so it shows with its icon instead of as a
  plain "Local dev" server. Just click **Install** when Claude Desktop asks; no restart needed.
- One fewer question: the Day One CLI is installed automatically (it's required). Installing Node.js
  still asks first.
- Works with **nvm** (Node Version Manager): nvm keeps separate global npm packages for each Node
  version, so after `nvm use` the Day One CLI could seem to vanish. The installer now looks in every
  nvm Node version and saves the CLI's real location (not nvm's "current version" shortcut).
- Windows: updating no longer fails with "the process cannot access the file" when Claude Desktop is
  running Day One MCP. The running copy is renamed aside (Windows allows that) and the new one put in
  place; Claude Desktop picks it up when it restarts. Old copies are cleaned up on the next run.
- Friendlier Claude Desktop prompt: "Claude Desktop needs a quick restart to connect Day One. Restart
  it now? It reopens when this finishes."

### MCP server
- Friendlier, clearer tool names and descriptions in Claude Desktop's tool permissions ("Search your
  journal", "Read an entry"...), each saying it's read-only. "Get your latest entries" (sync) is now
  marked read-only too, since it only downloads and never changes your journal, so all six tools sit
  together under **Read-only tools**.
- Also reads the Day One CLI location saved by the installer when it runs from somewhere else (the
  Claude Desktop extension or the Claude Code plugin), so nvm setups work there too.
- Also searches nvm's Node version folders for the Day One CLI (Windows: `C:\nvm4w`, `%LOCALAPPDATA%\nvm`,
  `%APPDATA%\nvm`, `NVM_HOME`; Mac/Linux: `~/.nvm`).
- Clearer message when the CLI can't be found: "Can't find the Day One CLI. Please re-run the Day One
  MCP installer".

## [1.0.2] - 22/11/2026

A new icon and kachihro branding, and friendlier installers. Search and reading are unchanged.

### Branding
- New app icon: a journal with a ribbon bookmark and the kachihro gem, on the kachihro gradient.
- The MCP server now sends a title ("Day One Journal by kachihro"), a description, a website link
  and the icon in its `serverInfo`, so MCP apps that show server icons pick it up.
- Plugin, marketplace and Claude Desktop extension names and descriptions mention kachihro.

### Installers
- Claude Desktop: if it's open, the installer and uninstaller offer to close it before saving the
  setting, because Claude Desktop can otherwise undo the change when it quits. It then checks the
  setting really saved, and reopens Claude Desktop at the end. Only Claude Desktop is closed, never
  Claude Code (Windows: Microsoft Store and regular installs; Mac: the Claude app).
- README: the `/dayone:` commands are Claude Code only; in Claude Desktop, just ask.
- Checks for Node.js 18 or newer (the Claude Code plugin needs it) and offers to install the current
  LTS (winget on Windows, Homebrew on Mac). Older versions still work for Claude Desktop.
- Headings are yellow instead of purple, so they're easier to read.

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
- The closing "Buy me a coffee (or a beer!)" line uses 💜 and a clickable link (OSC 8 terminal hyperlink, with the
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
