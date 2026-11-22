# Contributing

Thanks for helping! 💛 Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Please [open an issue](https://github.com/kachihro/dayone-mcp/issues/new/choose) and fill in the form. It asks for:

- your OS, and how you use it (Claude Code plugin, Claude Desktop, VS Code, ...)
- the output of `DayOneMcp --version` and `DayOneMcp --check` (Claude Code plugin users: the output of `/dayone:setup`).
  If you used the installer, the server is at `%LOCALAPPDATA%\Programs\dayone-mcp\DayOneMcp.exe` (Windows)
  or `~/.local/share/dayone-mcp/DayOneMcp` (Mac/Linux)
- `dayone --version`
- what you asked and what went wrong

**Never paste journal text, Day One passwords, encryption keys or tokens into an issue.**

## Project layout

| Path | What |
|---|---|
| `src/DayOneMcp/DayOneTools.cs` | The MCP tools Claude sees |
| `src/DayOneMcp/DayOneCli.cs` | Finds and runs the Day One CLI |
| `install.ps1`, `install.sh` | One-line installers |
| `packaging/mcpb/manifest.json` | Claude Desktop extension manifest |
| `.claude-plugin/marketplace.json` | Claude Code marketplace (lists the plugin) |
| `plugin/` | Claude Code plugin: `.mcp.json`, `launcher/` (downloads and runs the server), `skills/`, `hooks/` |
| `scripts/package.sh` | Builds all release packages |
| `tests/smoke_test.py` | End-to-end MCP test against the real Day One CLI |

## Development

```
dotnet build src/DayOneMcp
dotnet publish src/DayOneMcp -c Release -r linux-x64 -o out
python3 tests/smoke_test.py out/DayOneMcp "$(npm root -g)/@dayone/cli/node_modules/@dayone/cli-linux-x64-no-embeddings/dayone"
```

To test an installer against a local build, set `DAYONE_MCP_URL` to the package path, for example
`DAYONE_MCP_URL=file:///path/to/dayone-mcp-linux-x64.tar.gz bash install.sh`.

### Working on the Claude Code plugin

```
claude plugin validate --strict ./plugin
DAYONE_MCP_EXE=$PWD/out/DayOneMcp claude --plugin-dir ./plugin
```

`DAYONE_MCP_EXE` makes the launcher run your local build instead of downloading a release.
`DAYONE_MCP_DOWNLOAD_BASE` points the download at another server, for example a fork's releases.
Edits to skills take effect after `/reload-plugins`.

### README images and icon

The images in `docs/images/` and the app icon are made from HTML and SVG sources in
`docs/images/src/` (kachihro brand colours, Inter and JetBrains Mono fonts). Edit the source, then
re-render (needs Playwright with Chromium):

```
node docs/images/src/render.mjs              # everything
node docs/images/src/render.mjs hero steps   # just these
pngquant --quality=80-95 --force --ext .png docs/images/*.png   # optional: shrink them
```

The example journal text in the images is made up. Never use real journal entries.

## Guidelines

- Keep tools **read-only** unless there's a clear, opt-in reason not to. People's journals are precious.
- Pass arguments to the CLI with `ArgumentList` (never build a shell command string).
- Keep tool responses compact, because they use up the AI's context.
- Update `CHANGELOG.md`.

## Releasing (maintainers)

1. Update the version in **`plugin/.claude-plugin/plugin.json`** and the notes in `CHANGELOG.md`.
   The plugin downloads the release that matches its version, and the release build refuses to run
   if the two don't match.
2. Commit, then tag and push straight away: `git tag v1.0.1 && git push origin main v1.0.1`.
   Plugin users who update before the release finishes building get a download error until it's
   published, a few minutes later.
3. GitHub Actions builds every platform, runs the smoke test and publishes the release.
