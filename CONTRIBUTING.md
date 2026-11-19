# Contributing

Thanks for helping! 💛 Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Please include:

- your OS, and how you use it (Claude Code or Claude Desktop)
- the output of `DayOneMcp --version` and `DayOneMcp --check`
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

## Guidelines

- Keep tools **read-only** unless there's a clear, opt-in reason not to. People's journals are precious.
- Pass arguments to the CLI with `ArgumentList` (never build a shell command string).
- Keep tool responses compact, because they use up the AI's context.
- Update `CHANGELOG.md`.

## Releasing (maintainers)

1. Update the version and notes in `CHANGELOG.md`.
2. Tag and push: `git tag v1.0.1 && git push origin v1.0.1`.
3. GitHub Actions builds every platform, runs the smoke test and publishes the release.
