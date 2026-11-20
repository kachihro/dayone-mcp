<p align="center"><img src="packaging/mcpb/icon.svg" width="128" alt=""></p>

# Day One MCP for Claude

**Search your [Day One](https://dayoneapp.com) journal with AI, on Windows, Mac or Linux.**

Ask Claude things like:

- *"What did I write on this day in previous years?"*
- *"Find my entries about the beach from last summer and tell me how I was feeling."*
- *"When did I last mention Mum's birthday?"*
- *"Summarise my travel journal from 2024."*

It's a small, open-source [MCP server](https://modelcontextprotocol.io) that connects **Claude Code**
and **Claude Desktop** to Day One, using Day One's official cross-platform
[Day One CLI](https://github.com/Automattic/DayOne-Cli). It's **read-only**: Claude can search and read
your entries, but can't create, change or delete them.

> **On a Mac?** Day One has a built-in MCP server (Preferences → Labs, Silver or Gold). This project
> exists mainly for **Windows and Linux**, where there's no official option, but it works on Macs too.

---

## Install

### Claude Code plugin ⭐ (easiest for Claude Code)

In Claude Code, run:

```
/plugin install dayone --marketplace kachihro/dayone-mcp
```

(On Claude Code older than 2.1.275, run `/plugin marketplace add kachihro/dayone-mcp` first, then
`/plugin install dayone@dayone-mcp`.)

Then run **`/dayone:setup`**. Claude checks Node.js and the Day One CLI and walks you through signing
in to Day One. You'll sign in yourself in a terminal; Claude never sees your password. The plugin
downloads its server automatically the first time (about 40 MB, checked against the release's
SHA-256 checksums).

The plugin adds these commands:

| Command | What it does |
|---|---|
| `/dayone:on-this-day [date]` | Your memories from today (or any date) in past years |
| `/dayone:search <topic>` | Searches with several related keywords and summarises what it finds |
| `/dayone:reflect [period]` | Highlights, themes and mood for a period, e.g. `last month` or `2024` |
| `/dayone:setup` | Checks everything is working |

You can also just ask questions in plain English, like *"what was I worried about before the move?"*.
The plugin teaches Claude how to search a journal well.

### Everything at once: one-line installers

These set up the Day One CLI and connect **both** Claude Code (using the plugin above) and
Claude Desktop.

#### Windows

Open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1 | iex
```

#### macOS / Linux

Open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash
```

The installer walks you through everything and checks each step:

1. **Node.js**: offers to install it if you don't have it (it's needed by the Day One CLI)
2. **Day One CLI**: installs it, then signs you in to Day One and downloads your journals
3. **dayone-mcp**: downloads the latest release
4. **Claude**: installs the **Claude Code** plugin and connects **Claude Desktop**

Then:

- **Claude Code**: start a new session and try `/dayone:on-this-day`.
- **Claude Desktop**: fully quit it (tray icon → Quit on Windows, Cmd+Q on Mac) and reopen it.

Run the same command again any time to **update**.

### Claude Desktop only: double-click install (Windows)

1. Set up the Day One CLI in PowerShell (one-off; needs [Node.js LTS](https://nodejs.org)):
   ```powershell
   npm install -g @dayone/cli
   ```
   ```powershell
   dayone setup
   ```
   ```powershell
   dayone sync
   ```
2. Download **`dayone-mcp-win-x64.mcpb`** from the [latest release](https://github.com/kachihro/dayone-mcp/releases/latest).
3. Double-click it (or drag it onto **Claude Desktop → Settings → Extensions**) and click **Install**.

### Manual install

<details>
<summary>Prefer to do it by hand? Click here.</summary>

1. Install [Node.js LTS](https://nodejs.org), then the Day One CLI:
   ```
   npm install -g @dayone/cli
   dayone setup
   dayone sync
   ```
   If your journals use end-to-end encryption, also run `dayone auth key-set`.
2. Download the file for your computer from the [latest release](https://github.com/kachihro/dayone-mcp/releases/latest)
   and extract it (Windows: `dayone-mcp-win-x64.zip`; Apple silicon Mac: `dayone-mcp-osx-arm64.tar.gz`; and so on).
3. Add it to **Claude Code**:
   ```
   claude mcp add --scope user dayone -- "C:\path\to\DayOneMcp.exe"
   ```
4. Or add it to **Claude Desktop** (**Settings → Developer → Edit Config**):
   ```json
   {
     "mcpServers": {
       "dayone": { "command": "C:\\path\\to\\DayOneMcp.exe" }
     }
   }
   ```

</details>

### Uninstall

Plugin only (in Claude Code): `/plugin uninstall dayone@dayone-mcp`

Everything, Windows:
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1))) -Uninstall
```
Everything, macOS / Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash -s -- --uninstall
```

---

## What Claude can do

| Tool | What it does |
|---|---|
| `search_entries` | Keyword search, filtered by date range, journal, tags, starred or media (photos, audio and so on) |
| `on_this_day` | Entries from today (or any date) in previous years |
| `list_journals` | Your journals |
| `list_entries` | Browse a journal, newest or oldest first |
| `read_entry` | Read one entry in full |
| `sync_journals` | Download your latest entries from Day One |

Dates use your computer's local time zone, so an entry written at 11 pm stays on the right day.

**Keeping up to date:** searches use a local copy of your journals. Ask Claude to *"sync my journal"*,
or keep it fresh automatically:

```
dayone sync-schedule enable --interval-minutes 30
```

## How it works

```
Claude Code / Claude Desktop
        │  MCP (stdio)
        ▼
  DayOneMcp ── runs ──► Day One CLI (dayone) ──► local copy of your journals
                                 ▲
                                 └── dayone sync ◄── your Day One account
```

- Runs entirely on your computer. It has no servers and doesn't collect any data or analytics.
- Turns off the Day One CLI's optional telemetry for every command it runs.
- **Note:** the entries Claude reads to answer you are sent to Anthropic, like anything else you share
  in a chat. You choose what to ask about.

## Troubleshooting

| Problem | Fix |
|---|---|
| Something's not working in Claude Code | Run `/dayone:setup`. It checks each piece and tells you what to fix. |
| `plugin:dayone:dayone` failed in `/mcp` | The first start downloads the server, and on a slow connection that can time out. Restart Claude Code. |
| `dayone` doesn't show in `/mcp` | Start a **new** Claude Code session after installing. |
| "Could not find the Day One CLI" | Run the installer again. It saves the CLI's location next to the server. Or set `DAYONE_CLI_PATH` to the full path of the `dayone` executable (for the Claude Code plugin, add it under `"env"` in `~/.claude/settings.json`). |
| No results, or "run dayone sync first" | Run `dayone sync`, or ask Claude to sync. |
| Search misses things | On Windows and Intel Macs the Day One CLI only does keyword search (not meaning-based search). Ask Claude to try related words. |
| Encrypted journals show nothing | Run `dayone auth key-set` with your Day One encryption key. |
| Windows SmartScreen warning | The executable isn't code-signed yet. You can build it yourself from source (below). |
| Is it working? | Run `DayOneMcp --check` (Windows: `& "$env:LOCALAPPDATA\Programs\dayone-mcp\DayOneMcp.exe" --check`). |

Claude Desktop's server logs are in `%APPDATA%\Claude\logs` (Windows) or `~/Library/Logs/Claude` (Mac).

## Building from source

Needs the [.NET 10 SDK](https://dotnet.microsoft.com/download).

```
dotnet build src/DayOneMcp
dotnet publish src/DayOneMcp -c Release -r win-x64 -o out    # single self-contained executable
```

Run the smoke test (needs Python 3 and `npm install -g @dayone/cli`):

```
python3 tests/smoke_test.py out/DayOneMcp <path-to-dayone-binary>
```

Releases are built by GitHub Actions when a `v*` tag is pushed (see `scripts/package.sh`).

## Contributing

Ideas, bug reports and pull requests are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). 💛

## Disclaimer

This is an independent community project. It is **not affiliated with or endorsed by Day One or
Automattic**. "Day One" is a trademark of its owner. It uses the official, publicly available
[Day One CLI](https://github.com/Automattic/DayOne-Cli) and doesn't access any private APIs.

## License

[MIT](LICENSE)
