---
description: Check and finish setting up the Day One plugin (Node.js, the Day One CLI, sign-in and sync).
disable-model-invocation: true
allowed-tools: Bash(node --version), Bash(npm --version), Bash(dayone --version), Bash(dayone list journals), Bash(dayone doctor), mcp__plugin_dayone_dayone__list_journals, mcp__plugin_dayone_dayone__sync_journals
---

Help the user get the Day One plugin working. Go through these checks in order, tell them
briefly what you found at each step, and stop at the first thing that needs their action.

1. **Node.js**: run `node --version`. It needs version 18 or newer. If it's missing, ask them to
   install the LTS version from https://nodejs.org (on Windows: `winget install OpenJS.NodeJS.LTS`),
   then restart Claude Code.

2. **Day One CLI**: run `dayone --version`. If it's not found, offer to install it with
   `npm install -g @dayone/cli@latest`. Ask before running it.

3. **Signed in, with journals downloaded**: run `dayone list journals`.
   - If it returns journals, go to step 4.
   - If it returns none, or an error about signing in, the user must sign in **themselves in a
     separate terminal**, because it needs their Day One password. Never ask for their password or
     try to sign in for them. The easiest way is configure, which only does sign-in, the encryption key
     and sync (its prompts show `*` and accept pasting):
     - Windows (PowerShell): `irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/configure.ps1 | iex`
     - Mac/Linux (Terminal): `curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash`

     Then ask them to run `/dayone:setup` again. If sign-in says "Email and password combination not
     found" and they use Google or Apple to sign in to Day One, they need to set a password first
     (Forgot password at dayone.me).

4. **MCP server**: call the `list_journals` tool from the dayone plugin.
   - If it works, the setup is done. List their journals, and suggest trying `/dayone:on-this-day`,
     `/dayone:search <topic>` or `/dayone:reflect last month`.
   - If the tool isn't available, ask them to run `/mcp` and check `plugin:dayone:dayone`. The first
     start downloads the server (about 40 MB); if it timed out, restarting Claude Code usually fixes it.
   - If it reports it can't find the Day One CLI, run `dayone doctor`. If `dayone` works in a terminal
     but the server still can't find it (for example with an unusual Node.js setup), help them add the
     full path of the `dayone` executable to their Claude Code settings (`~/.claude/settings.json`):
     `"env": { "DAYONE_CLI_PATH": "<full path>" }`, then restart Claude Code.

5. Optionally suggest automatic syncing so new entries are always searchable:
   `dayone sync-schedule enable --interval-minutes 30`.
