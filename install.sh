#!/usr/bin/env bash
# One-line installer for dayone-mcp on macOS and Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash
#
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash -s -- --uninstall
#
# Options: --version vX.Y.Z  --yes  --skip-claude-code  --skip-claude-desktop  --uninstall
#
# Sets up: Node.js check -> Day One CLI (npm) + sign-in/sync -> dayone-mcp binary -> Claude Code + Claude Desktop.
# Safe to run again: it updates the server and skips steps that are already done.

set -euo pipefail

REPO="kachihro/dayone-mcp"
SERVER_NAME="dayone"
MARKETPLACE_NAME="dayone-mcp"
PLUGIN_ID="dayone@dayone-mcp"
MARKETPLACE_SOURCE="${DAYONE_MCP_MARKETPLACE:-$REPO}"   # for forks and testing
INSTALL_DIR="${DAYONE_MCP_HOME:-$HOME/.local/share/dayone-mcp}"
EXE="$INSTALL_DIR/DayOneMcp"
VERSION="${DAYONE_MCP_VERSION:-}"
YES=0; UNINSTALL=0; SKIP_CODE=0; SKIP_DESKTOP=0
export DO_NOT_TRACK=1   # keep the Day One CLI's optional telemetry off while we run it

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --yes|-y) YES=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --skip-claude-code) SKIP_CODE=1 ;;
    --skip-claude-desktop) SKIP_DESKTOP=1 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
step() { echo; c "36" "==> $1"; }
ok()   { c "32" "    [ok] $1"; }
info() { echo "    $1"; }
warn() { c "33" "    [!] $1"; }
has_tty() { (exec < /dev/tty) 2>/dev/null; }
ask() {
  [ "$YES" = 1 ] && return 0
  # stdin is this script when piped from curl, so read the answer from the terminal.
  if has_tty; then
    printf '    %s [Y/n] ' "$1" > /dev/tty
    read -r a < /dev/tty || a=""
    case "$a" in ""|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
  fi
  return 1
}

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Darwin) PLAT="osx"; DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"; NPM_PLAT="darwin" ;;
  Linux)  PLAT="linux"; DESKTOP_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json"; NPM_PLAT="linux" ;;
  *) echo "Unsupported OS: $OS (on Windows use install.ps1)" >&2; exit 1 ;;
esac
case "$ARCH" in
  x86_64|amd64) RID_ARCH="x64" ;;
  arm64|aarch64) RID_ARCH="arm64" ;;
  *) echo "Unsupported CPU: $ARCH" >&2; exit 1 ;;
esac
RID="$PLAT-$RID_ARCH"

# Edits mcpServers in claude_desktop_config.json with Node (always present, since the Day One CLI needs it).
desktop_config() { # $1 = add|remove
  [ -d "$(dirname "$DESKTOP_CFG")" ] || return 1
  [ -f "$DESKTOP_CFG" ] && cp "$DESKTOP_CFG" "$DESKTOP_CFG.bak"
  CFG="$DESKTOP_CFG" ACTION="$1" NAME="$SERVER_NAME" CMD="$EXE" node -e '
    const fs = require("fs"); const f = process.env.CFG;
    let cfg = {};
    try { const raw = fs.readFileSync(f, "utf8"); if (raw.trim()) cfg = JSON.parse(raw); } catch (e) { if (e.code !== "ENOENT") throw e; }
    cfg.mcpServers = cfg.mcpServers || {};
    if (process.env.ACTION === "add") cfg.mcpServers[process.env.NAME] = { command: process.env.CMD, args: [] };
    else delete cfg.mcpServers[process.env.NAME];
    fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + "\n");'
}

# Finds the Day One CLI's native binary inside npm's global folder (works even when 'node' is not on a GUI app's PATH).
find_dayone() {
  local root variants v p
  root="$(npm root -g 2>/dev/null || true)"
  [ -n "$root" ] || return 1
  if [ "$NPM_PLAT" = "linux" ]; then
    # Mirror the CLI's own choice: standard build needs glibc >= 2.39, otherwise the no-embeddings build.
    local glibc; glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
    if [ -n "$glibc" ] && [ "$(printf '%s\n2.39\n' "$glibc" | sort -V | head -1)" = "2.39" ]; then
      variants="linux-$RID_ARCH linux-$RID_ARCH-no-embeddings"
    else
      variants="linux-$RID_ARCH-no-embeddings linux-$RID_ARCH"
    fi
  else
    variants="darwin-$RID_ARCH"
  fi
  for v in $variants; do
    for p in "$root/@dayone/cli/node_modules/@dayone/cli-$v/dayone" "$root/@dayone/cli-$v/dayone"; do
      [ -x "$p" ] && { echo "$p"; return 0; }
    done
  done
  return 1
}

journal_count() {
  "$1" list journals 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).count||0)}catch{console.log(0)}})' 2>/dev/null || echo 0
}

echo
c "35" "  Day One MCP for Claude  -  https://github.com/$REPO"

# ------------------------------------------------------------------------------------------------ uninstall
if [ "$UNINSTALL" = 1 ]; then
  step "Uninstalling dayone-mcp"
  if [ "$SKIP_CODE" = 0 ] && command -v claude >/dev/null 2>&1; then
    claude plugin uninstall "$PLUGIN_ID" >/dev/null 2>&1 || true
    claude plugin marketplace remove "$MARKETPLACE_NAME" >/dev/null 2>&1 || true
    claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
    ok "Removed from Claude Code"
  fi
  if [ -f "$DESKTOP_CFG" ] && command -v node >/dev/null 2>&1; then desktop_config remove && ok "Removed from Claude Desktop (restart it to finish)"; fi
  rm -rf "$INSTALL_DIR" && ok "Deleted $INSTALL_DIR"
  info "The Day One CLI was left installed. Remove it with: npm uninstall -g @dayone/cli"
  exit 0
fi

if [ "$OS" = "Darwin" ]; then
  info "Tip: on a Mac you can also use Day One's own built-in MCP server (Preferences > Labs)."
fi

# ------------------------------------------------------------------------------------------------ 1. Node.js
step "Checking Node.js (needed by the Day One CLI)"
if ! command -v npm >/dev/null 2>&1; then
  warn "Node.js is not installed."
  if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1 && ask "Install Node.js with Homebrew?"; then
    brew install node
  fi
  command -v npm >/dev/null 2>&1 || { echo "Please install Node.js LTS from https://nodejs.org and run this again." >&2; exit 1; }
fi
ok "Node.js $(node --version)"

# ------------------------------------------------------------------------------------------------ 2. Day One CLI
step "Checking the Day One CLI"
DAYONE="$(find_dayone || true)"
if [ -z "$DAYONE" ]; then
  ask "Install the official Day One CLI (npm install -g @dayone/cli)?" || { echo "The Day One CLI is required." >&2; exit 1; }
  npm install -g @dayone/cli@latest || { echo "npm install failed. If it's a permissions error, see https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally" >&2; exit 1; }
  DAYONE="$(find_dayone || true)"
  [ -n "$DAYONE" ] || { echo "Installed @dayone/cli, but could not find its binary. Please open an issue on GitHub." >&2; exit 1; }
fi
ok "Day One CLI: $DAYONE"

JOURNALS="$(journal_count "$DAYONE")"
if [ "$JOURNALS" = "0" ]; then
  warn "No journals found yet. You need to sign in to Day One and download your journals."
  # Signing in is interactive (email + password), so it needs a terminal.
  if has_tty && ask 'Sign in now? (runs "dayone setup", then "dayone sync")'; then
    "$DAYONE" setup < /dev/tty || warn "Sign-in didn't finish."
    info "Downloading your journals (the first sync can take a few minutes)..."
    "$DAYONE" sync || warn "Sync didn't finish."
    JOURNALS="$(journal_count "$DAYONE")"
  fi
fi
if [ "$JOURNALS" != "0" ]; then ok "$JOURNALS journal(s) available"
else warn 'Still no journals. Run "dayone setup" and "dayone sync" later (and "dayone auth key-set" if your journals are encrypted).'; fi

# ------------------------------------------------------------------------------------------------ 3. dayone-mcp
step "Installing the dayone-mcp server"
if [ -n "${DAYONE_MCP_URL:-}" ]; then URL="$DAYONE_MCP_URL"   # for forks and testing (file:// works too)
elif [ -n "$VERSION" ]; then URL="https://github.com/$REPO/releases/download/$VERSION/dayone-mcp-$RID.tar.gz"
else URL="https://github.com/$REPO/releases/latest/download/dayone-mcp-$RID.tar.gz"; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
info "Downloading $URL"
curl -fsSL "$URL" -o "$TMP/dayone-mcp.tar.gz"
tar -xzf "$TMP/dayone-mcp.tar.gz" -C "$TMP"
mkdir -p "$INSTALL_DIR"
install -m 755 "$TMP/DayOneMcp" "$EXE"
[ "$OS" = "Darwin" ] && xattr -d com.apple.quarantine "$EXE" 2>/dev/null || true
printf '%s' "$DAYONE" > "$INSTALL_DIR/dayone-cli-path.txt"
ok "$("$EXE" --version) installed to $INSTALL_DIR"
if CHECK="$("$EXE" --check)"; then ok "$CHECK"; else warn "$CHECK"; fi

# ------------------------------------------------------------------------------------------------ 4. Claude
REGISTERED=""
if [ "$SKIP_CODE" = 0 ]; then
  step "Connecting to Claude Code"
  if command -v claude >/dev/null 2>&1; then
    # The Claude Code plugin brings the MCP server plus /dayone:* commands. It replaces any older
    # "claude mcp add" registration, so remove that first to avoid duplicate tools.
    claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
    # Refresh the marketplace so a re-run picks up new plugin versions, then install (or update).
    if claude plugin marketplace add "$MARKETPLACE_SOURCE" \
       && { claude plugin marketplace update "$MARKETPLACE_NAME" >/dev/null 2>&1 || true; } \
       && claude plugin install "$PLUGIN_ID" \
       && claude plugin update "$PLUGIN_ID"; then
      ok "Installed the Day One plugin for Claude Code"; REGISTERED="$REGISTERED code"
    else
      warn "Couldn't install the plugin, so adding the MCP server directly instead."
      if claude mcp add --scope user --transport stdio "$SERVER_NAME" -- "$EXE"; then ok "Added for all your projects (user scope)"; REGISTERED="$REGISTERED code"
      else warn "That didn't work either. In Claude Code, run: /plugin install dayone --marketplace $REPO"; fi
    fi
  else
    info "Claude Code isn't installed (or not on PATH). Later, in Claude Code run:"
    info "  /plugin install dayone --marketplace $REPO"
  fi
fi

if [ "$SKIP_DESKTOP" = 0 ]; then
  step "Connecting to Claude Desktop"
  if desktop_config add; then ok "Updated $DESKTOP_CFG (backup saved as .bak)"; REGISTERED="$REGISTERED desktop"
  else info "Claude Desktop isn't installed. Run this installer again after installing it."; fi
fi

echo
c "32" "  All done!"
case "$REGISTERED" in *desktop*) echo "  - Claude Desktop: fully quit it (Cmd+Q / Quit) and reopen it." ;; esac
case "$REGISTERED" in *code*) echo "  - Claude Code: start a new session and try /dayone:on-this-day (or /dayone:setup to check everything)." ;; esac
echo "  Then ask: 'What did I write on this day in previous years?'"
echo
