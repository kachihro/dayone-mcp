<p align="center"><a href="../README.md"><img src="../packaging/mcpb/icon.svg" width="72" alt="Day One MCP"></a></p>

# Troubleshooting

**First, try these two:**

1. **Run the installer again.** It's safe to re-run, skips what's already done, and fixes most things.
   Windows: `irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1 | iex` ·
   Mac/Linux: `curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash`
2. **In Claude Code, run `/dayone:setup`.** It checks each piece and tells you what to fix.

| Problem | Fix |
|---|---|
| Is it working at all? | Windows: `& "$env:LOCALAPPDATA\Programs\dayone-mcp\DayOneMcp.exe" --check` · Mac/Linux: `~/.local/share/dayone-mcp/DayOneMcp --check` |
| The installer didn't connect Claude | Install Claude Desktop or Claude Code first, then run the installer again. |
| No journals, or "run dayone sync first" | Run **configure**: it signs you in and downloads your journals ([commands](../README.md#-commands-at-a-glance)). Or run `dayone sync`. |
| "Email and password combination not found" | Check for typos (the installer shows `*` for each character). If you sign in to Day One with Google or Apple, set a password first with **Forgot password** at [dayone.me](https://dayone.me). |
| Encrypted journals show nothing, or "no verified journal key" | Run **configure** ([commands](../README.md#-commands-at-a-glance)). It notices, shows where to find your key, and checks the key unlocks your entries. By hand: `dayone auth key-set`, then `dayone sync`. |
| "Can't find the Day One CLI" | Re-run the installer. It finds the CLI (including in any Node version managed by **nvm**) or installs it, and reconnects it. Or tell the server where it is with [`DAYONE_CLI_PATH`](#setting-dayone_cli_path). |
| "Node.js is too old" | The Claude Code plugin needs Node.js 18 or newer. Let the installer install the current LTS, or get it from [nodejs.org](https://nodejs.org), then open a new terminal. Using **nvm**? Run `nvm install --lts` and `nvm use --lts`. |
| Windows: "the process cannot access the file" | Fixed in the current installer: it now replaces the server even while Claude Desktop is using it. Run the installer again. |
| Claude Code: `plugin:dayone:dayone` failed in `/mcp` | The first start downloads the server, which can time out on a slow connection. Restart Claude Code. |
| Claude Code: tools don't appear | Start a **new** session after installing. |
| Claude Desktop: **dayone** isn't in Settings → Plugins | Run the installer again and let it restart Claude Desktop. If Claude Desktop is open while the setting is saved, it can undo the change when it quits. |
| Claude Desktop: "dayone stopped running" | Click **View logs** on the message. Logs are also in `%APPDATA%\Claude\logs` (Windows) or `~/Library/Logs/Claude` (Mac). Please [open an issue](https://github.com/kachihro/dayone-mcp/issues/new/choose) with the last few lines. |
| Claude Desktop: "`/dayone` isn't installed" | The `/dayone:` commands are Claude Code only. In Claude Desktop, just ask in plain English, e.g. *"When did I go to Hamburg?"* |
| Search misses things | On Windows and Intel Macs, search matches your words exactly. Try related words, or use `/dayone:search` in Claude Code, which does this for you. |
| Windows SmartScreen warning | The program isn't code-signed yet. Choose **More info → Run anyway**, or build it yourself (see [CONTRIBUTING.md](../CONTRIBUTING.md)). |

## Setting `DAYONE_CLI_PATH`

Only needed if the server can't find the Day One CLI by itself.

First, find the full path of the Day One CLI program:

- **Windows** (PowerShell): `Join-Path (npm root -g) '@dayone\cli\node_modules\@dayone\cli-win32-x64\dayone.exe'`.
  Don't use `where.exe dayone`, which finds a launcher script rather than the program itself.
- **Mac/Linux:** `which dayone`

Then set it for your app:

- **Claude Desktop / VS Code / Cursor:** add `"env": { "DAYONE_CLI_PATH": "<path>" }` next to `"command"` in the `dayone` entry.
- **Claude Code plugin:** add `"env": { "DAYONE_CLI_PATH": "<path>" }` to `~/.claude/settings.json`, then restart Claude Code.

Remember to use double backslashes (`\\`) for Windows paths in JSON.

## Start again from scratch

1. Run **uninstall** ([commands](../README.md#-commands-at-a-glance)) and answer **y** to also remove the Day One CLI.
2. Restart Claude Desktop and Claude Code.
3. Run the **install** command again.

Your journals always stay safe in your Day One account.

## Still stuck?

[Open an issue](https://github.com/kachihro/dayone-mcp/issues/new/choose). Please don't include journal text,
passwords or encryption keys.

---

[← Back to the README](../README.md)
