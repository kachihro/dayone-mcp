#!/usr/bin/env bash
# Day One MCP installer for macOS and Linux.
#
#   Install:    curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.sh | bash
#   Configure:  curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/configure.sh | bash
#   Uninstall:  curl -fsSL https://raw.githubusercontent.com/kachihro/dayone-mcp/main/uninstall.sh | bash
#
# Options: --configure  --uninstall [--everything]  --version vX.Y.Z  --yes
#          --skip-claude-code  --skip-claude-desktop
#
# Part 1 "Adding Day One MCP": Node.js, the Day One CLI, the server, Claude Code and Claude Desktop.
# Part 2 "Setting it up for you": your Day One sign-in, encryption key and journals.
# Safe to run again: it updates the server and skips what's already done.
#
# Written for bash 3.2, because that's what macOS runs for "curl ... | bash".

set -euo pipefail

REPO="kachihro/dayone-mcp"
SERVER_NAME="dayone"
MARKETPLACE_NAME="dayone-mcp"
PLUGIN_ID="dayone@dayone-mcp"
MARKETPLACE_SOURCE="${DAYONE_MCP_MARKETPLACE:-$REPO}"   # for forks and testing
INSTALL_DIR="${DAYONE_MCP_HOME:-$HOME/.local/share/dayone-mcp}"
EXE="$INSTALL_DIR/DayOneMcp"
VERSION="${DAYONE_MCP_VERSION:-}"
YES=0; UNINSTALL=0; CONFIGURE=0; EVERYTHING=0; SKIP_CODE=0; SKIP_DESKTOP=0
export DO_NOT_TRACK=1   # keep the Day One CLI's optional telemetry off while we run it

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --yes|-y) YES=1 ;;
    --configure) CONFIGURE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --everything) EVERYTHING=1 ;;
    --skip-claude-code) SKIP_CODE=1 ;;
    --skip-claude-desktop) SKIP_DESKTOP=1 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Darwin) PLAT="osx"; NPM_PLAT="darwin"; DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  Linux)  PLAT="linux"; NPM_PLAT="linux"; DESKTOP_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
  *) echo "Unsupported OS: $OS (on Windows use install.ps1)" >&2; exit 1 ;;
esac
case "$ARCH" in
  x86_64|amd64) RID_ARCH="x64" ;;
  arm64|aarch64) RID_ARCH="arm64" ;;
  *) echo "Unsupported CPU: $ARCH" >&2; exit 1 ;;
esac
RID="$PLAT-$RID_ARCH"

# ------------------------------------------------------------------------------------------------ output
# Emoji on a Mac or any UTF-8 terminal; plain text otherwise.
FANCY=0
case "$OS:${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in Darwin:*|*UTF-8*|*utf-8*|*UTF8*|*utf8*) FANCY=1 ;; esac
[ -n "${NO_COLOR:-}" ] && FANCY=0

col() { printf '\033[%sm%s\033[0m' "$1" "$2"; }
icon() { # emoji for a name; plain-text fallback when FANCY=0
  if [ "$FANCY" = 1 ]; then
    case "$1" in
      book) printf '📔' ;; plus) printf '➕' ;; person) printf '👤' ;; node) printf '📦' ;;
      rocket) printf '🚀' ;; bolt) printf '⚡️' ;; desktop) printf '💻' ;; key) printf '🔐' ;;
      keyhole) printf '🔑' ;; broom) printf '🧹' ;; ok) printf '✅' ;; warn) printf '❗' ;;
      party) printf '🎉' ;; arrow) printf '👉' ;; coffee) printf '☕️' ;; heart) printf '💜' ;;
    esac
  fi
}
part() { # icon, title
  echo
  if [ "$FANCY" = 1 ]; then
    local n=$((52 - ${#2})); [ $n -lt 4 ] && n=4
    printf '%s ' "$(icon "$1")"; col 35 "$2"; printf ' \033[90m%s\033[0m\n' "$(printf '%*s' "$n" '' | sed 's/ /─/g')"
  else
    col 35 "== $2 =="; echo
  fi
}
step() { echo; if [ "$FANCY" = 1 ]; then printf '%s ' "$(icon "$1")"; col 36 "$2"; echo; else col 36 "==> $2"; echo; fi; }
ok()   { if [ "$FANCY" = 1 ]; then printf '   %s ' "$(icon ok)"; col 32 "$1"; echo; else col 32 "    [ok] $1"; echo; fi; }
warn() { if [ "$FANCY" = 1 ]; then printf '   %s ' "$(icon warn)"; col 33 "$1"; echo; else col 33 "    [!] $1"; echo; fi; }
info() { printf '    %s\n' "$1"; }
done_line() { if [ "$FANCY" = 1 ]; then printf '   %s %s\n' "$(icon arrow)" "$1"; else printf '    - %s\n' "$1"; fi; }

# ------------------------------------------------------------------------------------------------ input
# When piped from curl, stdin is this script, so questions are read from the terminal instead.
TTY="${DAYONE_MCP_TTY:-/dev/tty}"   # can be pointed at a file of answers for testing
HAS_TTY=0
if [ -r "$TTY" ] && { exec 3<"$TTY"; } 2>/dev/null; then HAS_TTY=1; fi

ask() { # Yes/no question that defaults to Yes
  [ "$YES" = 1 ] && return 0
  [ "$HAS_TTY" = 1 ] || return 1
  local a=""; printf '    %s [Y/n] ' "$1"; IFS= read -r -u 3 a || a=""
  [ ! -t 3 ] && echo "$a"
  case "$a" in ""|y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}
ask_no() { # Yes/no question that defaults to No (for anything that removes your data)
  [ "$HAS_TTY" = 1 ] || return 1
  local a=""; printf '    %s [y/N] ' "$1"; IFS= read -r -u 3 a || a=""
  [ ! -t 3 ] && echo "$a"
  case "$a" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}
ask_text() { # prompt -> REPLY_TEXT
  REPLY_TEXT=""; printf '    %s: ' "$1"; IFS= read -r -u 3 REPLY_TEXT || REPLY_TEXT=""
  [ ! -t 3 ] && echo "$REPLY_TEXT"
  return 0
}
ask_secret() { # prompt -> REPLY_SECRET. Shows * for each character, accepts pasting, supports backspace.
  REPLY_SECRET=""; local c=""
  printf '    %s: ' "$1"
  while IFS= read -r -s -n 1 -u 3 c; do
    [ -z "$c" ] && break                                   # Enter
    if [ "$c" = $'\x7f' ] || [ "$c" = $'\b' ]; then       # Backspace
      if [ -n "$REPLY_SECRET" ]; then REPLY_SECRET="${REPLY_SECRET%?}"; printf '\b \b'; fi
      continue
    fi
    REPLY_SECRET="$REPLY_SECRET$c"; printf '*'
  done
  echo
}

# ------------------------------------------------------------------------------------------------ helpers
OUT=""
quiet() { # runs a command, keeping its output in $OUT (shown only if something goes wrong)
  local rc=0; OUT="$("$@" 2>&1)" || rc=$?; return $rc
}
show_out() { [ -n "$OUT" ] && printf '%s\n' "$OUT" | sed 's/^/      /' | tail -n 8 | while IFS= read -r l; do col 90 "$l"; echo; done; return 0; }

# Runs a small piece of JavaScript over JSON on stdin (Node is always present: the Day One CLI needs it).
json() {
  JS="$1" node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      let o = null;
      try { const i = s.indexOf("{"), j = s.lastIndexOf("}"); if (i >= 0 && j > i) o = JSON.parse(s.slice(i, j + 1)); } catch {}
      try { const v = new Function("o", process.env.JS)(o); if (v !== undefined && v !== null) console.log(v); } catch {}
    });' 2>/dev/null || true
}

# "Signed in as Alex Rivers (Silver)": just the key details from the account record.
format_signed_in() {
  printf '%s' "$1" | json '
    const u = (o && o.user) || {}; let s = "Signed in";
    if (u.display_name) s += " as " + u.display_name;
    const p = u.feature_bundle && u.feature_bundle.bundle_name;
    if (p) s += " (" + p.charAt(0).toUpperCase() + p.slice(1) + ")";
    return s;'
}

# "3 journals: Personal, Travel, Work" (at most 4 names).
format_journals() {
  "$DAYONE" list journals 2>/dev/null | json '
    const items = (o && o.items) || []; if (!items.length) return "";
    const names = items.map(j => j.name).filter(Boolean);
    const label = items.length === 1 ? "1 journal" : items.length + " journals";
    if (!names.length) return label + " ready";
    return label + ": " + names.slice(0, 4).join(", ") + (names.length > 4 ? ", ..." : "");'
}

# Edits mcpServers in claude_desktop_config.json.
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
  local root variants v p glibc
  command -v npm >/dev/null 2>&1 || return 1
  root="$(npm root -g 2>/dev/null || true)"
  [ -n "$root" ] || return 1
  if [ "$NPM_PLAT" = "linux" ]; then
    # Mirror the CLI's own choice: standard build needs glibc >= 2.39, otherwise the no-embeddings build.
    glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
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

key_steps() {
  echo
  if [ "$FANCY" = 1 ]; then printf '    %s ' "$(icon keyhole)"; col 36 "Get your key:"; echo; else col 36 "    Get your key:"; echo; fi
  info "  1. Open Day One on your Mac, phone or dayone.me"
  info "  2. Go to:  Mac: Day One > Settings > Sync > Advanced > View Encryption Key"
  info "             iPhone / Android: profile picture > Sync > Encryption Key"
  info "             dayone.me: Settings > Account > Encryption Key"
  info "  3. Copy the key (it starts with D1-) and paste it below"
  echo
}

# 1480 -> 1,480 (bash 3.2-safe)
fmt_num() { local n="$1" r=""; while [ ${#n} -gt 3 ]; do r=",${n: -3}$r"; n="${n:0:$((${#n} - 3))}"; done; printf '%s%s' "$n" "$r"; }

# Draws a live status line from the Day One CLI's progress lines as they arrive:
#   "[sync] resource start kind=entries key=entries:<journal>"  -> next journal
#   "[sync] resource page key=entries:<journal> items=<n> ..."  -> n more entries
#   "[sync] resource done kind=entries ... changed_count=<n>"   -> fallback entry count
# Writes the final entry count to the file given as $1.
sync_progress() {
  local journal=0 pages=0 done=0 tick=0 count frame text line
  local frames
  if [ "$FANCY" = 1 ]; then frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); else frames=('|' '/' '-' '\'); fi
  local dot="-"; [ "$FANCY" = 1 ] && dot="·"
  while IFS= read -r line; do
    case "$line" in
      *"resource start kind=entries"*) journal=$((journal + 1)) ;;
      *"resource page key=entries:"*) [[ $line =~ items=([0-9]+) ]] && pages=$((pages + BASH_REMATCH[1])) ;;
      *"resource done kind=entries"*) [[ $line =~ changed_count=([0-9]+) ]] && done=$((done + BASH_REMATCH[1])) ;;
    esac
    tick=$((tick + 1)); count=$pages; [ $done -gt $count ] && count=$done
    frame="${frames[$((tick % ${#frames[@]}))]}"
    if [ $journal -gt 0 ]; then text="Syncing journal $journal  $dot  $(fmt_num "$count") entries"; else text="Syncing your account..."; fi
    printf '\r    \033[36m%s %-60s\033[0m' "$frame" "$text"
  done
  printf '\r%74s\r' ''
  count=$pages; [ $done -gt $count ] && count=$done
  printf '%s' "$count" > "$1"
}

# Syncs journals. Sets SYNC_RESULT (ok / needs-key / failed) and SYNCED (entries synced).
SYNC_RESULT=""; SYNCED=0
sync_dayone() {
  local log countf rc=0
  log="$(mktemp)"; countf="$(mktemp)"
  set +e
  "$DAYONE" sync 2>&1 | tee "$log" | sync_progress "$countf"
  rc=${PIPESTATUS[0]}
  set -e
  OUT="$(cat "$log")"; SYNCED="$(cat "$countf" 2>/dev/null || echo 0)"; rm -f "$log" "$countf"
  case "$OUT" in *"no verified journal key"*) SYNC_RESULT="needs-key"; return 0 ;; esac
  if [ $rc -eq 0 ]; then SYNC_RESULT="ok"; else SYNC_RESULT="failed"; fi
}

sign_in() { # returns 0 when signed in
  local email try=1
  ask_text "Email"; email="$REPLY_TEXT"
  while [ $try -le 3 ]; do
    ask_secret "Password"
    if OUT="$(printf '%s\n' "$REPLY_SECRET" | "$DAYONE" auth login --email "$email" --password-stdin 2>&1)"; then
      REPLY_SECRET=""
      ok "$(format_signed_in "$OUT")"
      return 0
    fi
    REPLY_SECRET=""
    warn "Wrong email or password. (Sign in with Google or Apple? Set a password first at dayone.me.)"
    try=$((try + 1))
  done
  return 1
}

unlock() { # asks for the encryption key until the entries unlock, or the person skips
  local try=1
  warn "Your journals are end-to-end encrypted, so they need your encryption key."
  key_steps
  while [ $try -le 3 ]; do
    ask_secret "Encryption key (D1-..., or press Enter to skip)"
    if [ -z "$REPLY_SECRET" ]; then info "Skipped. Run configure any time to add it."; return 1; fi
    if ! OUT="$(printf '%s\n' "$REPLY_SECRET" | "$DAYONE" auth key-set --key-stdin 2>&1)"; then
      REPLY_SECRET=""; warn "That doesn't look like a Day One encryption key (it starts with D1-)."
      try=$((try + 1)); continue
    fi
    REPLY_SECRET=""
    info "Unlocking your entries"
    sync_dayone
    if [ "$SYNC_RESULT" != "needs-key" ]; then ok "Encryption key saved, $(fmt_num "$SYNCED") entries unlocked"; return 0; fi
    warn "That key didn't unlock your entries. Check it and try again."
    try=$((try + 1))
  done
  return 1
}

# Part 2: the personal bits. Prints nothing extra; sets JOURNALS_LINE.
JOURNALS_LINE=""
personal_setup() {
  local signed_in=0 result
  step key "Your Day One account"
  if quiet "$DAYONE" auth whoami; then
    signed_in=1
    ok "$(format_signed_in "$OUT")"
    if [ "$CONFIGURE" = 1 ] && [ "$YES" = 0 ] && [ "$HAS_TTY" = 1 ] && ! ask "Keep using this account?"; then
      quiet "$DAYONE" auth logout || quiet "$DAYONE" auth logout --force || true
      info "Signed out."
      signed_in=0
    fi
  fi
  if [ $signed_in = 0 ] && [ "$YES" = 0 ] && [ "$HAS_TTY" = 1 ]; then
    if sign_in; then signed_in=1; fi
  fi

  step book "Your journals"
  if [ $signed_in = 0 ]; then warn "Not signed in yet. Run configure any time to sign in."; return 0; fi
  info "Syncing (the first time can take a few minutes)"
  sync_dayone; result="$SYNC_RESULT"
  if [ "$result" = "ok" ]; then
    if [ "$SYNCED" -gt 0 ] 2>/dev/null; then ok "Synced $(fmt_num "$SYNCED") entries"; else ok "Up to date"; fi
  fi
  if [ "$result" = "needs-key" ]; then
    if [ "$YES" = 1 ] || [ "$HAS_TTY" = 0 ] || ! unlock; then
      warn "Encrypted entries stay locked until you add your key (run configure)."
    fi
  elif [ "$result" = "failed" ]; then
    warn "Sync didn't finish. Check your internet connection, then run: dayone sync"
  fi
  JOURNALS_LINE="$(format_journals)"
  if [ -n "$JOURNALS_LINE" ]; then ok "$JOURNALS_LINE"; else warn "No journals found in your Day One account yet."; fi
}

# ------------------------------------------------------------------------------------------------ start
echo
if [ "$FANCY" = 1 ]; then printf '  %s ' "$(icon book)"; col 35 "Day One MCP"; printf '  \033[90mby kachihro %s\033[0m\n' "$(icon heart)"
else col 35 "  Day One MCP  -  by kachihro"; echo; fi
printf '  \033[90mgithub.com/%s\033[0m\n' "$REPO"

# ------------------------------------------------------------------------------------------------ uninstall
if [ "$UNINSTALL" = 1 ]; then
  part broom "Uninstalling Day One MCP"
  step bolt "Claude"
  if [ "$SKIP_CODE" = 0 ] && command -v claude >/dev/null 2>&1; then
    quiet claude plugin uninstall "$PLUGIN_ID" || true
    quiet claude plugin marketplace remove "$MARKETPLACE_NAME" || true
    quiet claude mcp remove --scope user "$SERVER_NAME" || true
    ok "Removed from Claude Code"
  fi
  if [ -f "$DESKTOP_CFG" ] && command -v node >/dev/null 2>&1; then desktop_config remove && ok "Removed from Claude Desktop"; fi
  if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; ok "Removed the server"; fi

  # Optionally go back to a clean slate: sign out, remove the Day One CLI and what it downloaded.
  DAYONE="$(find_dayone || true)"
  CLI_DIRS="${XDG_CONFIG_HOME:-$HOME/.config}/dayone-cli|$HOME/.config/dayone-cli|$HOME/Library/Application Support/dayone-cli"
  HAS_CLI=0; [ -n "$DAYONE" ] && HAS_CLI=1
  OLDIFS="$IFS"; IFS='|'; for d in $CLI_DIRS; do [ -d "$d" ] && HAS_CLI=1; done; IFS="$OLDIFS"
  if [ $HAS_CLI = 1 ]; then
    step person "Day One CLI"
    if [ "$EVERYTHING" = 0 ] && [ "$YES" = 0 ]; then
      info "Your journals stay safe in your Day One account either way."
      if ask_no "Also sign out and remove the Day One CLI and its downloaded copy of your journals?"; then EVERYTHING=1; fi
    fi
    if [ "$EVERYTHING" = 1 ]; then
      if [ -n "$DAYONE" ]; then
        quiet "$DAYONE" sync-schedule disable || true
        quiet "$DAYONE" auth logout || quiet "$DAYONE" auth logout --force || true
        ok "Signed out of Day One"
      fi
      if command -v npm >/dev/null 2>&1; then
        if quiet npm uninstall -g @dayone/cli; then ok "Removed the Day One CLI"; else warn "Couldn't remove the Day One CLI:"; show_out; fi
      fi
      OLDIFS="$IFS"; IFS='|'; for d in $CLI_DIRS; do [ -d "$d" ] && rm -rf "$d"; done; IFS="$OLDIFS"
      ok "Removed its settings and downloaded journals"
    else
      info "Kept the Day One CLI and your sign-in."
    fi
  fi

  echo
  if [ "$FANCY" = 1 ]; then printf '%s ' "$(icon ok)"; col 32 "Uninstalled."; echo; else col 32 "  Uninstalled."; echo; fi
  done_line "Restart Claude Desktop and Claude Code to finish."
  done_line "To start again: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
  echo
  exit 0
fi

# ------------------------------------------------------------------------------------------------ configure only
if [ "$CONFIGURE" = 1 ]; then
  DAYONE="$(find_dayone || true)"
  if [ -z "$DAYONE" ] || ! command -v node >/dev/null 2>&1; then
    warn "Day One MCP is not installed yet. Run the installer first:"
    info "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
    echo; exit 0
  fi
  part person "Setting it up for you"
  personal_setup
  echo
  if [ -n "$JOURNALS_LINE" ]; then
    if [ "$FANCY" = 1 ]; then printf '%s ' "$(icon party)"; col 32 "All set! Your journals are ready for Claude."; echo; else col 32 "  All set! Your journals are ready for Claude."; echo; fi
    done_line "Ask Claude: 'What did I write on this day in previous years?'"
  fi
  echo
  exit 0
fi

# ================================================================================================ Part 1: adding it
part plus "Part 1 - Adding Day One MCP"

step node "Checking what you need"
if ! command -v npm >/dev/null 2>&1; then
  warn "Node.js is needed (the Day One CLI runs on it)."
  if [ "$OS" = "Darwin" ] && command -v brew >/dev/null 2>&1 && ask "Install Node.js now (with Homebrew)?"; then
    info "Installing Node.js..."
    quiet brew install node || { warn "Installing Node.js failed:"; show_out; }
  fi
  command -v npm >/dev/null 2>&1 || { warn "Please install Node.js LTS from https://nodejs.org and run this again."; exit 1; }
fi
ok "Node.js $(node --version)"

DAYONE="$(find_dayone || true)"
if [ -z "$DAYONE" ]; then
  ask "Install the Day One CLI?" || { warn "The Day One CLI is required."; exit 1; }
  info "Installing the Day One CLI..."
  if ! quiet npm install -g @dayone/cli@latest; then
    warn "Installing the Day One CLI failed:"; show_out
    info "If it's a permissions error: https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally"
    exit 1
  fi
  DAYONE="$(find_dayone || true)"
  [ -n "$DAYONE" ] || { warn "Installed the Day One CLI, but couldn't find it. Please open an issue on GitHub."; exit 1; }
fi
ok "Day One CLI"

step rocket "Day One MCP server"
if [ -n "${DAYONE_MCP_URL:-}" ]; then URL="$DAYONE_MCP_URL"   # for forks and testing (file:// works too)
elif [ -n "$VERSION" ]; then URL="https://github.com/$REPO/releases/download/$VERSION/dayone-mcp-$RID.tar.gz"
else URL="https://github.com/$REPO/releases/latest/download/dayone-mcp-$RID.tar.gz"; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if ! quiet curl -fsSL "$URL" -o "$TMP/dayone-mcp.tar.gz"; then warn "Download failed:"; show_out; exit 1; fi
tar -xzf "$TMP/dayone-mcp.tar.gz" -C "$TMP"
mkdir -p "$INSTALL_DIR"
install -m 755 "$TMP/DayOneMcp" "$EXE"
if [ "$OS" = "Darwin" ]; then xattr -d com.apple.quarantine "$EXE" 2>/dev/null || true; fi
printf '%s' "$DAYONE" > "$INSTALL_DIR/dayone-cli-path.txt"
ok "$("$EXE" --version)"
# Only mention the health check if the server can't find the Day One CLI.
CHECK_RC=0; CHECK="$("$EXE" --check 2>&1)" || CHECK_RC=$?
[ $CHECK_RC -eq 1 ] && warn "$CHECK"

REGISTERED=""
if [ "$SKIP_CODE" = 0 ]; then
  step bolt "Claude Code"
  if command -v claude >/dev/null 2>&1; then
    # The Claude Code plugin brings the MCP server plus /dayone:* commands. It replaces any older
    # "claude mcp add" registration, so remove that first to avoid duplicate tools.
    quiet claude mcp remove --scope user "$SERVER_NAME" || true
    # Refresh the marketplace so a re-run picks up new plugin versions, then install (or update).
    if quiet claude plugin marketplace add "$MARKETPLACE_SOURCE" \
       && { quiet claude plugin marketplace update "$MARKETPLACE_NAME" || true; } \
       && quiet claude plugin install "$PLUGIN_ID" \
       && quiet claude plugin update "$PLUGIN_ID"; then
      ok "Plugin installed"; REGISTERED="$REGISTERED code"
    else
      show_out
      warn "Couldn't install the plugin, so connecting the server directly instead."
      if quiet claude mcp add --scope user --transport stdio "$SERVER_NAME" -- "$EXE"; then ok "Connected"; REGISTERED="$REGISTERED code"
      else show_out; warn "That didn't work either. In Claude Code, run: /plugin install dayone --marketplace $REPO"; fi
    fi
  else
    info "Not installed. Later, in Claude Code run: /plugin install dayone --marketplace $REPO"
  fi
fi

if [ "$SKIP_DESKTOP" = 0 ]; then
  step desktop "Claude Desktop"
  if desktop_config add; then ok "Connected"; REGISTERED="$REGISTERED desktop"
  else info "Not installed. Run this installer again after installing it."; fi
fi

# ================================================================================================ Part 2: for you
part person "Part 2 - Setting it up for you"
personal_setup

echo
if [ "$FANCY" = 1 ]; then printf '%s ' "$(icon party)"; col 32 "All done!"; echo; else col 32 "  All done!"; echo; fi
case "$REGISTERED" in *desktop*) done_line "Claude Desktop: quit it fully (Cmd+Q), then reopen" ;; esac
case "$REGISTERED" in *code*) done_line "Claude Code: start a new session and try /dayone:on-this-day" ;; esac
[ -z "$JOURNALS_LINE" ] && done_line "Later: sign in or add your key with configure.sh (see the README)"
if [ "$OS" = "Darwin" ]; then info "Tip: Day One for Mac also has its own MCP server (Settings > Labs)."; fi
echo
if [ "$FANCY" = 1 ]; then printf '   %s \033[90mEnjoying it? ko-fi.com/kachihro\033[0m\n' "$(icon coffee)"; fi
echo
