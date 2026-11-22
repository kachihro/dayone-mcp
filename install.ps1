<#
.SYNOPSIS
    One-line installer for dayone-mcp on Windows.

.DESCRIPTION
    Sets up everything needed to search your Day One journal from Claude Code and Claude Desktop:

      1. Node.js            (offers to install it with winget if missing)
      2. Day One CLI        (npm install -g @dayone/cli, then sign in and sync)
      3. dayone-mcp server  (latest GitHub release -> %LOCALAPPDATA%\Programs\dayone-mcp)
      4. Registers it with Claude Code and Claude Desktop

    Safe to run again: it updates the server and skips steps that are already done.

.EXAMPLE
    # Install or update (paste into PowerShell):
    irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1 | iex

.EXAMPLE
    # Uninstall:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1))) -Uninstall

.EXAMPLE
    # Options can also be set with environment variables before piping to iex:
    $env:DAYONE_MCP_VERSION = 'v1.0.0'; irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1 | iex
#>
param(
    [string] $Version = $env:DAYONE_MCP_VERSION,          # e.g. v1.0.0 (default: latest)
    [switch] $Uninstall = [bool]$env:DAYONE_MCP_UNINSTALL,
    [switch] $Configure = [bool]$env:DAYONE_MCP_CONFIGURE,
    [switch] $Everything = [bool]$env:DAYONE_MCP_EVERYTHING, # with -Uninstall: also sign out and remove the Day One CLI and its data   # only sign in, add your key and sync (what configure.ps1 runs)
    [switch] $SkipClaudeCode = [bool]$env:DAYONE_MCP_SKIP_CLAUDE_CODE,
    [switch] $SkipClaudeDesktop = [bool]$env:DAYONE_MCP_SKIP_CLAUDE_DESKTOP,
    [switch] $Yes = [bool]$env:DAYONE_MCP_YES             # answer "yes" to every prompt
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster on Windows PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo       = 'kachihro/dayone-mcp'
$ServerName = 'dayone'
$MarketplaceName = 'dayone-mcp'
$PluginId = 'dayone@dayone-mcp'
$MarketplaceSource = if ($env:DAYONE_MCP_MARKETPLACE) { $env:DAYONE_MCP_MARKETPLACE } else { $Repo }   # for forks and testing
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\dayone-mcp'
$ExePath    = Join-Path $InstallDir 'DayOneMcp.exe'
$env:DO_NOT_TRACK = '1'   # keep the Day One CLI's optional telemetry off while we run it

# Emoji where the terminal can show them (Windows Terminal, PowerShell 7, VS Code); plain text in the
# old console. They're built from code points so this file stays plain ASCII for Windows PowerShell 5.1.
$Fancy = [bool]($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode' -or $PSVersionTable.PSVersion.Major -ge 7)
function U([int[]] $CodePoints) { -join ($CodePoints | ForEach-Object { [char]::ConvertFromUtf32($_) }) }
$Icon = @{
    book = U 0x1F4D4; node = U 0x1F4E6; key = U 0x1F510; rocket = U 0x1F680; bolt = U 0x26A1, 0xFE0F
    desktop = U 0x1F4BB; ok = U 0x2705; warn = U 0x2757; party = U 0x1F389
    broom = U 0x1F9F9; heart = U 0x1F49C; arrow = U 0x1F449; keyhole = U 0x1F511; plus = U 0x2795; person = U 0x1F464
}

function Step($iconName, $t) { Write-Host ''; if ($Fancy) { Write-Host "$($Icon[$iconName]) $t" -ForegroundColor Cyan } else { Write-Host "==> $t" -ForegroundColor Cyan } }
function Ok($t)    { if ($Fancy) { Write-Host "   $($Icon.ok) $t" -ForegroundColor Green } else { Write-Host "    [ok] $t" -ForegroundColor Green } }
# A clickable link (OSC 8 terminal hyperlink) in terminals that support it; just the text elsewhere.
# The text is the full https:// address, so terminals without OSC 8 can still detect it as a link.
function Link([string] $Url, [string] $Text = $Url) {
    if (-not $Fancy) { return $Text }
    $e = [string][char]27
    return "$e]8;;$Url$e\$Text$e]8;;$e\"
}
function Info($t)  { Write-Host "    $t" -ForegroundColor Gray }
function Warn($t)  { if ($Fancy) { Write-Host "   $($Icon.warn) $t" -ForegroundColor Yellow } else { Write-Host "    [!] $t" -ForegroundColor Yellow } }
function Ask($q) {
    if ($Yes) { return $true }
    $a = Read-Host "    $q [Y/n]"
    return ($a -eq '' -or $a -match '^(y|yes)$')
}
# Like Ask, but defaults to No: for anything that removes your data.
function AskNo($q) {
    $a = Read-Host "    $q [y/N]"
    return ($a -match '^(y|yes)$')
}
# Runs a native command without letting its stderr output become a terminating error
# (Windows PowerShell 5.1 does that when $ErrorActionPreference is 'Stop'). Returns the exit code.
# Output is captured and only shown if the command fails (or never, with -Quiet), which keeps the
# installer short. Tools like npm and claude write UTF-8, so read it as UTF-8 to avoid garbled text.
function Invoke-Native([scriptblock] $NativeBlock, [switch] $Quiet) {
    $oldPref = $ErrorActionPreference
    $oldEnc = [Console]::OutputEncoding
    $ErrorActionPreference = 'Continue'
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        $out = & $NativeBlock 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        $script:NativeOutput = $out   # kept so callers can pick out a few values
        if ($code -ne 0 -and -not $Quiet) { $out | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
        return $code
    } finally {
        [Console]::OutputEncoding = $oldEnc
        $ErrorActionPreference = $oldPref
    }
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Claude Desktop keeps its config in %APPDATA%\Claude, or a virtualised folder for the Microsoft Store build.
function Get-DesktopConfigPath {
    $store = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($store) { return (Join-Path $store 'claude_desktop_config.json') }
    $classic = Join-Path $env:APPDATA 'Claude'
    if (Test-Path $classic) { return (Join-Path $classic 'claude_desktop_config.json') }
    return $null
}

# Claude Desktop's own processes (Microsoft Store or regular install). Never Claude Code, which is also
# claude.exe (including the copy inside Claude Desktop's Code tab, under ...\Claude\claude-code\).
function Get-ClaudeDesktopProcess {
    return @(Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path -match '[\\/](WindowsApps[\\/]Claude_|AnthropicClaude[\\/])' -and $_.Path -notmatch '[\\/]claude-code[\\/]'
    })
}

# Claude Desktop rewrites claude_desktop_config.json from memory, so a change made while it's open can be
# lost. This offers to close it (and waits until it has really gone). Returns $true if it isn't running.
$script:ClosedDesktop = $false
function Close-ClaudeDesktop([string] $Why) {
    $procs = Get-ClaudeDesktopProcess
    if ($procs.Count -eq 0) { return $true }
    $codeTab = @(Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.Path -match '[\\/]claude-code[\\/]' }).Count -gt 0
    Info "Claude Desktop needs a quick restart to $Why."
    $q = if ($codeTab) { 'Restart it now? It reopens when this finishes. (Claude Code sessions in its Code tab will close.)' }
         else { 'Restart it now? It reopens when this finishes.' }
    if (-not (Ask $q)) { return $false }
    foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 12 -and (Get-ClaudeDesktopProcess).Count -gt 0; $i++) { Start-Sleep -Milliseconds 250 }
    # Electron apps often just hide in the tray when their window closes, so finish the job.
    Get-ClaudeDesktopProcess | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and (Get-ClaudeDesktopProcess).Count -gt 0; $i++) { Start-Sleep -Milliseconds 250 }
    if ((Get-ClaudeDesktopProcess).Count -gt 0) { Warn "Couldn't close Claude Desktop."; return $false }
    $script:ClosedDesktop = $true
    Ok 'Closed Claude Desktop (it reopens at the end)'
    return $true
}

# Reopens Claude Desktop through its Start menu entry (works for the Microsoft Store and regular installs).
function Open-ClaudeDesktop {
    $app = $null
    try { $app = Get-StartApps -ErrorAction Stop | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1 } catch { }
    if (-not $app) { return $false }
    try { Start-Process "shell:AppsFolder\$($app.AppID)"; return $true } catch { return $false }
}

# True if claude_desktop_config.json has our server pointing at this install.
function Test-DesktopConfig([string] $Path) {
    try { return ((Get-Content $Path -Raw | ConvertFrom-Json).mcpServers.$ServerName.command -eq $ExePath) } catch { return $false }
}

# Reads claude_desktop_config.json, applies $Change to its mcpServers, writes it back (UTF-8, no BOM).
function Update-DesktopConfig([string] $Path, [scriptblock] $Change) {
    $config = [ordered]@{}
    if (Test-Path $Path) {
        Copy-Item $Path "$Path.bak" -Force
        $raw = [IO.File]::ReadAllText($Path)
        if ($raw.Trim()) {
            $parsed = $raw | ConvertFrom-Json
            foreach ($p in $parsed.PSObject.Properties) { $config[$p.Name] = $p.Value }
        }
    }
    $servers = [ordered]@{}
    if ($config.Contains('mcpServers') -and $config['mcpServers']) {
        foreach ($p in $config['mcpServers'].PSObject.Properties) { $servers[$p.Name] = $p.Value }
    }
    & $Change $servers
    $config['mcpServers'] = $servers
    $json = $config | ConvertTo-Json -Depth 50
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}

# Finds the native dayone.exe inside npm's global folder (calling it directly avoids cmd.exe quoting issues).
function Find-DayOneExe {
    $ErrorActionPreference = 'Continue'   # local to this function (see Invoke-Native)
    $roots = @()
    try { $roots += (& npm root -g 2>$null | Select-Object -First 1) } catch { }
    $roots += (Join-Path $env:APPDATA 'npm\node_modules')
    # nvm keeps separate global packages for each Node version, so also look in every version's folder
    # (newest first). The Day One CLI's own program doesn't need Node, so any copy works.
    foreach ($nvm in @($env:NVM_HOME, (Join-Path $env:LOCALAPPDATA 'nvm'), (Join-Path $env:APPDATA 'nvm'), 'C:\nvm4w') | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path $nvm) {
            Get-ChildItem $nvm -Directory -Filter 'v*' -ErrorAction SilentlyContinue |
                Sort-Object { try { [version]($_.Name.TrimStart('v')) } catch { [version]'0.0' } } -Descending |
                ForEach-Object { $roots += (Join-Path $_.FullName 'node_modules') }
        }
    }
    foreach ($root in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
        foreach ($rel in @('@dayone\cli\node_modules\@dayone\cli-win32-x64\dayone.exe', '@dayone\cli-win32-x64\dayone.exe')) {
            $p = Join-Path $root.Trim() $rel
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

# The real location of a file, following any folder shortcut (symlink or junction) on the way.
# nvm reaches the active Node version through one (e.g. C:\nvm4w\nodejs), and that changes with
# "nvm use", so the real path is what keeps working.
function Resolve-RealPath([string] $Path) {
    $probe = $Path
    while ($probe) {
        $item = Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -and $item.Target) {
            $target = @($item.Target)[0]
            if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path $probe -Parent) $target }
            $rest = $Path.Substring($probe.Length).TrimStart('\', '/')
            $real = if ($rest) { Join-Path $target $rest } else { $target }
            if (Test-Path -LiteralPath $real) { return (Resolve-RealPath $real) }
            return $Path
        }
        $parent = Split-Path $probe -Parent
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
    return $Path
}

# Puts a new DayOneMcp.exe in place. If the current one is running (e.g. Claude Desktop started it),
# Windows won't let it be overwritten, but it does let it be renamed: so move it aside and copy the new
# one in. The old copy keeps running until Claude Desktop restarts, and is cleaned up next time.
function Install-ServerExe([string] $Source) {
    Get-ChildItem $InstallDir -Filter 'DayOneMcp.exe.old-*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    if (Test-Path $ExePath) {
        try { Copy-Item $Source $ExePath -Force -ErrorAction Stop; return }
        catch { Move-Item $ExePath "$ExePath.old-$((Get-Date).ToString('yyyyMMddHHmmss'))" -Force -ErrorAction Stop }
    }
    Copy-Item $Source $ExePath -Force -ErrorAction Stop
}

# Pipes a SecureString's text straight into a program's stdin, then forgets it. Returns the exit code.
# (It must pipe into the program itself: text piped into a script block doesn't reach a program inside it.)
function Send-Secret([System.Security.SecureString] $Secret, [string] $Exe, [string[]] $ExeArgs) {
    $OutputEncoding = New-Object Text.UTF8Encoding $false   # keep non-ASCII characters intact (PowerShell 5.1)
    $text = (New-Object System.Net.NetworkCredential('', $Secret)).Password
    try { return (Invoke-Native -Quiet { $text | & $Exe @ExeArgs }) }
    finally { $text = $null; $Secret.Dispose() }
}

# "Signed in as Alex Rivers (Silver)": just the key details from the account record.
function Format-SignedIn($User) {
    $who = 'Signed in'
    if ($User.display_name) { $who += " as $($User.display_name)" }
    if ($User.feature_bundle.bundle_name) { $who += " ($((Get-Culture).TextInfo.ToTitleCase($User.feature_bundle.bundle_name)))" }
    return $who
}

# Signs in with PowerShell's secure prompts: they show * as you type and accept pasting,
# unlike the hidden prompt in "dayone setup". Nothing is shown on screen or saved in history.
function Connect-DayOne([string] $DayOneExe) {
    $email = (Read-Host '    Email').Trim()
    for ($try = 1; $try -le 3; $try++) {
        $password = Read-Host '    Password' -AsSecureString
        $code = Send-Secret $password $DayOneExe @('auth', 'login', '--email', $email, '--password-stdin')
        if ($code -eq 0) {
            # Show just who signed in and their plan, not the whole account record.
            Ok (Format-SignedIn (ConvertFrom-JsonOutput $script:NativeOutput).user)
            return $true
        }
        Warn 'Wrong email or password. (Sign in with Google or Apple? Set a password first at dayone.me.)'
    }
    return $false
}

# True if the Day One CLI already has a signed-in session.
function Test-DayOneSignedIn([string] $DayOneExe) {
    return ((Invoke-Native -Quiet { & $DayOneExe auth whoami }) -eq 0)
}

# Syncs journals. Returns 'ok', 'needs-key' (encrypted entries it couldn't unlock) or 'failed'.
# Shows a live status line while syncing, by reading the Day One CLI's progress lines as they arrive:
#   "[sync] resource start kind=entries key=entries:<journal>"  -> next journal
#   "[sync] resource page key=entries:<journal> items=<n> ..."  -> n more entries
#   "[sync] resource done kind=entries ... changed_count=<n>"   -> fallback entry count
# Sets $script:SyncedEntries. Returns 'ok', 'needs-key' (encrypted entries it couldn't unlock) or 'failed'.
function Sync-DayOne([string] $DayOneExe) {
    $frames = if ($Fancy) { @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F) | ForEach-Object { [string][char]$_ } }
              else { @('|', '/', '-', '\') }
    $dot = if ($Fancy) { [string][char]0x00B7 } else { '-' }
    $lines = New-Object System.Collections.Generic.List[string]
    $state = @{ journal = 0; pages = 0; done = 0; tick = 0 }
    $oldPref = $ErrorActionPreference; $oldEnc = [Console]::OutputEncoding
    $ErrorActionPreference = 'Continue'
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
        & $DayOneExe sync 2>&1 | ForEach-Object {
            $l = "$_"; $lines.Add($l)
            if ($l -match 'resource start kind=entries') { $state.journal++ }
            elseif ($l -match 'resource page key=entries:\S+ items=(\d+)') { $state.pages += [int]$Matches[1] }
            elseif ($l -match 'resource done kind=entries .*changed_count=(\d+)') { $state.done += [int]$Matches[1] }
            $state.tick++
            $count = [Math]::Max($state.pages, $state.done)
            $text = if ($state.journal -gt 0) { "Syncing journal $($state.journal)  $dot  {0:N0} entries" -f $count } else { 'Syncing your account...' }
            Write-Host -NoNewline ("`r    $($frames[$state.tick % $frames.Count]) $text".PadRight(72)) -ForegroundColor Cyan
        }
        $code = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $oldEnc
        $ErrorActionPreference = $oldPref
        Write-Host -NoNewline ("`r" + (' ' * 74) + "`r")   # clear the status line
    }
    $script:NativeOutput = $lines
    $script:SyncedEntries = [Math]::Max($state.pages, $state.done)
    if (($lines -join "`n") -match 'no verified journal key') { return 'needs-key' }
    if ($code -ne 0) { return 'failed' }
    return 'ok'
}

# Asks for the encryption key (secure prompt) until the entries unlock, or the person skips.
function Unlock-DayOne([string] $DayOneExe) {
    Warn 'Your journals are end-to-end encrypted, so they need your encryption key.'
    Write-Host ''
    if ($Fancy) { Write-Host "    $($Icon.keyhole) Get your key:" -ForegroundColor Cyan } else { Write-Host '    Get your key:' -ForegroundColor Cyan }
    Info '  1. Open Day One on your phone, the Windows app or dayone.me'
    Info '  2. Go to:  iPhone / Android: profile picture > Sync > Encryption Key'
    Info '             Windows / dayone.me: Settings > Account > Encryption Key'
    Info '  3. Copy the key (it starts with D1-) and paste it below'
    Write-Host ''
    for ($try = 1; $try -le 3; $try++) {
        $key = Read-Host '    Encryption key (D1-..., or press Enter to skip)' -AsSecureString
        if ($key.Length -eq 0) { Info 'Skipped. Run configure.ps1 any time to add it.'; return $false }
        if ((Send-Secret $key $DayOneExe @('auth', 'key-set', '--key-stdin')) -ne 0) {
            Warn "That doesn't look like a Day One encryption key (it starts with D1-)."
            continue
        }
        Info 'Unlocking your entries'
        if ((Sync-DayOne $DayOneExe) -ne 'needs-key') { Ok ('Encryption key saved, {0:N0} entries unlocked' -f $script:SyncedEntries); return $true }
        Warn "That key didn't unlock your entries. Check it and try again."
    }
    return $false
}

# Pulls the JSON object out of a command's captured output (ignoring any warning lines around it).
function ConvertFrom-JsonOutput([string[]] $Lines) {
    $text = ($Lines -join "`n")
    $start = $text.IndexOf('{'); $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    try { return ($text.Substring($start, $end - $start + 1) | ConvertFrom-Json) } catch { return $null }
}

# Returns the user's journals (objects with at least a name), or an empty list.
function Get-Journals([string] $DayOneExe) {
    $ErrorActionPreference = 'Continue'   # local to this function: stderr warnings must not abort the read
    try { $json = & $DayOneExe list journals 2>$null | Out-String | ConvertFrom-Json } catch { return @() }
    if ($json -and $json.items) { return @($json.items) }
    return @()
}
function Get-JournalCount([string] $DayOneExe) { return @(Get-Journals $DayOneExe).Count }

# "3 journals: Personal, Travel, Work" (at most 4 names).
function Format-Journals($Journals) {
    $n = @($Journals).Count
    $names = @($Journals | ForEach-Object { $_.name } | Where-Object { $_ })
    $label = if ($n -eq 1) { '1 journal' } else { "$n journals" }
    if ($names.Count -eq 0) { return "$label ready" }
    $shown = ($names | Select-Object -First 4) -join ', '
    if ($names.Count -gt 4) { $shown += ', ...' }
    return "${label}: $shown"
}

# Part headings: "Part 1 - Adding Day One MCP" / "Part 2 - Setting it up for you".
function Part($iconName, $title) {
    Write-Host ''
    if ($Fancy) { Write-Host "$($Icon[$iconName]) $title " -ForegroundColor Yellow -NoNewline; Write-Host ([string][char]0x2500 * [Math]::Max(4, 52 - $title.Length)) -ForegroundColor DarkGray }
    else        { Write-Host "== $title ==" -ForegroundColor Yellow }
}

# Part 2: the personal bits. Your Day One account, encryption key and journals.
function Invoke-PersonalSetup([string] $DayOneExe) {
    # Signing in and the encryption key need a person at the keyboard, so skip those prompts with -Yes.
    Step key 'Your Day One account'
    $signedIn = $false
    if ((Invoke-Native -Quiet { & $DayOneExe auth whoami }) -eq 0) {
        $signedIn = $true
        Ok (Format-SignedIn (ConvertFrom-JsonOutput $script:NativeOutput).user)
        if ($Configure -and -not $Yes -and -not (Ask 'Keep using this account?')) {
            if ((Invoke-Native -Quiet { & $DayOneExe auth logout }) -ne 0) { Invoke-Native -Quiet { & $DayOneExe auth logout --force } | Out-Null }
            Info 'Signed out.'
            $signedIn = $false
        }
    }
    if (-not $signedIn -and -not $Yes) { $signedIn = Connect-DayOne $DayOneExe }

    Step book 'Your journals'
    if (-not $signedIn) {
        Warn 'Not signed in yet. Run configure.ps1 any time to sign in.'
        return 0
    }
    Info 'Syncing (the first time can take a few minutes)'
    $sync = Sync-DayOne $DayOneExe
    if ($sync -eq 'ok') {
        if ($script:SyncedEntries -gt 0) { Ok ('Synced {0:N0} entries' -f $script:SyncedEntries) } else { Ok 'Up to date' }
    }
    if ($sync -eq 'needs-key') {
        if ($Yes -or -not (Unlock-DayOne $DayOneExe)) { Warn 'Encrypted entries stay locked until you add your key (run configure.ps1).' }
    } elseif ($sync -eq 'failed') {
        Warn "Sync didn't finish. Check your internet connection, then run: dayone sync"
    }
    $journals = @(Get-Journals $DayOneExe)
    if ($journals.Count -gt 0) { Ok (Format-Journals $journals) } else { Warn 'No journals found in your Day One account yet.' }
    return $journals.Count
}

Write-Host ''
if ($Fancy) { Write-Host "  $($Icon.book) Day One MCP  " -ForegroundColor Yellow -NoNewline; Write-Host "by kachihro $($Icon.heart)" -ForegroundColor DarkGray }
else        { Write-Host '  Day One MCP  -  by kachihro' -ForegroundColor Yellow }
Write-Host '  github.com/kachihro/dayone-mcp' -ForegroundColor DarkGray

# ---------------------------------------------------------------------------------------------- uninstall
if ($Uninstall) {
    Part broom 'Uninstalling Day One MCP'
    Step bolt 'Claude'
    if (-not $SkipClaudeCode -and (Get-Command claude -ErrorAction SilentlyContinue)) {
        Invoke-Native -Quiet { claude plugin uninstall "$PluginId" } | Out-Null
        Invoke-Native -Quiet { claude plugin marketplace remove $MarketplaceName } | Out-Null
        Invoke-Native -Quiet { claude mcp remove --scope user $ServerName } | Out-Null
        Ok 'Removed from Claude Code'
    }
    $cfg = Get-DesktopConfigPath
    if ($cfg -and (Test-Path $cfg) -and (Select-String -Path $cfg -Pattern "`"$ServerName`"" -Quiet)) {
        $closed = Close-ClaudeDesktop 'remove Day One'
        Update-DesktopConfig $cfg { param($s) $s.Remove($ServerName) }
        Ok 'Removed from Claude Desktop'
        if (-not $closed) { Warn 'Quit Claude Desktop fully (tray icon > Quit), then run uninstall again to be sure.' }
    }
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Ok 'Removed the server'
        # Windows can't delete a program that's still running (Claude Desktop may have started it).
        if (Test-Path $InstallDir) { Info "One file is still in use. After restarting Claude Desktop you can delete: $InstallDir" }
    }

    # Optionally go back to a clean slate: sign out, remove the Day One CLI and what it downloaded.
    $dayoneExe = Find-DayOneExe
    $cliDirs = @((Join-Path $env:APPDATA 'dayone-cli'), (Join-Path $env:LOCALAPPDATA 'dayone-cli'),
                 (Join-Path $HOME '.config\dayone-cli')) | Select-Object -Unique
    $hasCli = $dayoneExe -or ($cliDirs | Where-Object { Test-Path $_ })
    if ($hasCli) {
        Step person 'Day One CLI'
        if (-not $Everything -and -not $Yes) {
            Info 'Your journals stay safe in your Day One account either way.'
            $Everything = AskNo 'Also sign out and remove the Day One CLI and its downloaded copy of your journals?'
        }
        if ($Everything) {
            if ($dayoneExe) {
                Invoke-Native -Quiet { & $dayoneExe sync-schedule disable } | Out-Null
                if ((Invoke-Native -Quiet { & $dayoneExe auth logout }) -ne 0) { Invoke-Native -Quiet { & $dayoneExe auth logout --force } | Out-Null }
                Ok 'Signed out of Day One'
            }
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                if ((Invoke-Native { npm uninstall -g '@dayone/cli' }) -eq 0) { Ok 'Removed the Day One CLI' }
            }
            foreach ($d in $cliDirs) { if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue } }
            Ok 'Removed its settings and downloaded journals'
        } else {
            Info 'Kept the Day One CLI and your sign-in.'
        }
    }

    Write-Host ''
    if ($Fancy) { Write-Host "$($Icon.ok) Uninstalled." -ForegroundColor Green } else { Write-Host '  Uninstalled.' -ForegroundColor Green }
    $arrow = if ($Fancy) { "   $($Icon.arrow)" } else { '    -' }
    if ($script:ClosedDesktop -and (Open-ClaudeDesktop)) { Write-Host "$arrow Reopened Claude Desktop. Restart Claude Code to finish." }
    else { Write-Host "$arrow Restart Claude Desktop and Claude Code to finish." }
    Write-Host "$arrow To start again: irm https://raw.githubusercontent.com/$Repo/main/install.ps1 | iex"
    Write-Host ''
    return
}

# ---------------------------------------------------------------------------------------------- configure only
if ($Configure) {
    $dayoneExe = Find-DayOneExe
    if (-not $dayoneExe -or -not (Get-Command node -ErrorAction SilentlyContinue)) {
        Warn 'Day One MCP is not installed yet. Run the installer first:'
        Info "  irm https://raw.githubusercontent.com/$Repo/main/install.ps1 | iex"
        Write-Host ''
        return
    }
    Part person 'Setting it up for you'
    $journals = Invoke-PersonalSetup $dayoneExe
    Write-Host ''
    if ($journals -gt 0) {
        if ($Fancy) { Write-Host "$($Icon.party) All set! Your journals are ready for Claude." -ForegroundColor Green } else { Write-Host '  All set! Your journals are ready for Claude.' -ForegroundColor Green }
        $arrow = if ($Fancy) { "   $($Icon.arrow)" } else { '    -' }
        Write-Host "$arrow Ask Claude: 'What did I write on this day in previous years?'"
    }
    Write-Host ''
    return
}

if ($env:PROCESSOR_ARCHITECTURE -notin @('AMD64', 'ARM64')) {
    throw 'dayone-mcp needs 64-bit Windows.'
}

# ============================================================================================== Part 1: adding it
Part plus 'Part 1 - Adding Day One MCP'

# ---------------------------------------------------------------------------------------------- Node.js + Day One CLI
Step node 'Checking what you need'
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Warn 'Node.js is needed (the Day One CLI runs on it).'
    if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Ask 'Install Node.js now?')) {
        Info 'Installing Node.js...'
        Invoke-Native { winget install --id OpenJS.NodeJS.LTS --exact --silent --accept-package-agreements --accept-source-agreements } | Out-Null
        Refresh-Path
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'Please install Node.js LTS from https://nodejs.org, open a new PowerShell window, and run this again.'
    }
}
# Node.js 18 or newer: the Claude Code plugin's launcher needs it (Node 16 and older are out of support).
function Get-NodeMajor { $v = "$(& node --version 2>$null)"; if ($v -match '^v(\d+)') { return [int]$Matches[1] } return 0 }
$nodeVersion = "$(& node --version 2>$null)"
if ((Get-NodeMajor) -lt 18) {
    Warn "Node.js $nodeVersion is too old: version 18 or newer is needed (for the Claude Code plugin)."
    if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Ask 'Install the current Node.js LTS now?')) {
        Info 'Installing Node.js LTS...'
        $code = Invoke-Native -Quiet { winget install --id OpenJS.NodeJS.LTS --exact --silent --accept-package-agreements --accept-source-agreements }
        if ($code -ne 0) { Invoke-Native -Quiet { winget upgrade --id OpenJS.NodeJS.LTS --exact --silent --accept-package-agreements --accept-source-agreements } | Out-Null }
        Refresh-Path
        $nodeVersion = "$(& node --version 2>$null)"
    }
    if ((Get-NodeMajor) -lt 18) {
        Warn 'Still using an older Node.js. Install the LTS from https://nodejs.org, open a new PowerShell window and run this again.'
        Info 'Claude Desktop will still work; the Claude Code plugin needs the newer Node.js.'
    }
}
if ((Get-NodeMajor) -ge 18) { Ok "Node.js $nodeVersion" }

$dayoneExe = Find-DayOneExe
if (-not $dayoneExe) {
    Info 'Installing the Day One CLI...'
    if ((Invoke-Native { npm install -g '@dayone/cli@latest' }) -ne 0) { throw 'Installing the Day One CLI failed (see above).' }
    Refresh-Path
    $dayoneExe = Find-DayOneExe
    if (-not $dayoneExe) { throw 'Installed the Day One CLI, but could not find dayone.exe. Please open an issue on GitHub.' }
}
Ok 'Day One CLI'

# ---------------------------------------------------------------------------------------------- dayone-mcp
Step rocket 'Day One MCP server'
$localExe = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'DayOneMcp.exe' } else { $null }
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

if ($localExe -and (Test-Path $localExe)) {
    Install-ServerExe $localExe
} else {
    $url = if ($env:DAYONE_MCP_URL) { $env:DAYONE_MCP_URL }   # for forks and testing
           elseif ($Version) { "https://github.com/$Repo/releases/download/$Version/dayone-mcp-win-x64.zip" }
           else              { "https://github.com/$Repo/releases/latest/download/dayone-mcp-win-x64.zip" }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dayone-mcp-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp 'dayone-mcp.zip') -UseBasicParsing
        Expand-Archive (Join-Path $tmp 'dayone-mcp.zip') -DestinationPath $tmp -Force
        Install-ServerExe (Join-Path $tmp 'DayOneMcp.exe')
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Unblock-File $ExePath -ErrorAction SilentlyContinue
[IO.File]::WriteAllText((Join-Path $InstallDir 'dayone-cli-path.txt'), (Resolve-RealPath $dayoneExe), (New-Object Text.UTF8Encoding $false))
Ok "$(& $ExePath --version)"

# Only mention the health check if the server can't find the Day One CLI.
$check = & $ExePath --check
if ($LASTEXITCODE -eq 1) { Warn $check }

# ---------------------------------------------------------------------------------------------- Claude
$registered = @()

if (-not $SkipClaudeCode) {
    Step bolt 'Claude Code'
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        # The Claude Code plugin brings the MCP server plus /dayone:* commands. It replaces any
        # older "claude mcp add" registration, so remove that first to avoid duplicate tools.
        Invoke-Native -Quiet { claude mcp remove --scope user $ServerName } | Out-Null
        $code = Invoke-Native { claude plugin marketplace add $MarketplaceSource }
        if ($code -eq 0) {
            # Refresh the marketplace so a re-run picks up new plugin versions, then install (or update).
            Invoke-Native -Quiet { claude plugin marketplace update $MarketplaceName } | Out-Null
            $code = Invoke-Native { claude plugin install "$PluginId" }
            if ($code -eq 0) { Invoke-Native -Quiet { claude plugin update "$PluginId" } | Out-Null }
        }
        if ($code -eq 0) {
            Ok 'Plugin installed'
            $registered += 'Claude Code'
        } else {
            Warn "Couldn't install the plugin, so connecting the server directly instead."
            $code = Invoke-Native { claude mcp add --scope user --transport stdio $ServerName -- $ExePath }
            if ($code -eq 0) { Ok 'Connected'; $registered += 'Claude Code' }
            else { Warn "That didn't work either. In Claude Code, run: /plugin install dayone --marketplace $Repo" }
        }
    } else {
        Info 'Not installed. Later, in Claude Code run: /plugin install dayone --marketplace kachihro/dayone-mcp'
    }
}

if (-not $SkipClaudeDesktop) {
    Step desktop 'Claude Desktop'
    $cfg = Get-DesktopConfigPath
    if ($cfg) {
        $closed = Close-ClaudeDesktop 'connect Day One'
        Update-DesktopConfig $cfg { param($s) $s[$ServerName] = [ordered]@{ command = $ExePath; args = @() } }
        if (Test-DesktopConfig $cfg) {
            Ok 'Connected'
            $registered += 'Claude Desktop'
            if (-not $closed) { $script:DesktopStillOpen = $true }
        } else {
            Warn "Couldn't save the Claude Desktop setting. Quit Claude Desktop and run this installer again."
        }
    } else {
        Info 'Not installed. Run this installer again after installing it.'
    }
}

# ============================================================================================== Part 2: for you
Part person 'Part 2 - Setting it up for you'
$journals = Invoke-PersonalSetup $dayoneExe

# ---------------------------------------------------------------------------------------------- done
Write-Host ''
if ($Fancy) { Write-Host "$($Icon.party) All done!" -ForegroundColor Green } else { Write-Host '  All done!' -ForegroundColor Green }
$arrow = if ($Fancy) { "   $($Icon.arrow)" } else { '    -' }
if ($registered -contains 'Claude Desktop') {
    if ($script:DesktopStillOpen) { Write-Host "$arrow Claude Desktop: quit it fully (tray icon > Quit), then run this installer again" }
    elseif ($script:ClosedDesktop -and (Open-ClaudeDesktop)) { Write-Host "$arrow Claude Desktop: reopened. Start a new chat and ask about your journal" }
    else { Write-Host "$arrow Claude Desktop: open it and start a new chat" }
}
if ($registered -contains 'Claude Code')    { Write-Host "$arrow Claude Code: start a new session and try /dayone:on-this-day" }
if ($journals -eq 0) { Write-Host "$arrow Later: sign in or add your key with configure.ps1 (see the README)" }
Write-Host ''
if ($Fancy) { Write-Host "   $($Icon.heart) Enjoying it? Buy me a coffee (or a beer!): $(Link 'https://ko-fi.com/kachihro')" -ForegroundColor DarkGray }
Write-Host ''
