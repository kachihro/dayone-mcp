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
    desktop = U 0x1F4BB; ok = U 0x2705; warn = U 0x2757; party = U 0x1F389; coffee = U 0x2615, 0xFE0F
    broom = U 0x1F9F9; heart = U 0x1F49C; arrow = U 0x1F449
}

function Step($icon, $t) { Write-Host ''; if ($Fancy) { Write-Host "$($Icon[$icon]) $t" -ForegroundColor Cyan } else { Write-Host "==> $t" -ForegroundColor Cyan } }
function Ok($t)    { if ($Fancy) { Write-Host "   $($Icon.ok) $t" -ForegroundColor Green } else { Write-Host "    [ok] $t" -ForegroundColor Green } }
function Info($t)  { Write-Host "    $t" -ForegroundColor Gray }
function Warn($t)  { if ($Fancy) { Write-Host "   $($Icon.warn) $t" -ForegroundColor Yellow } else { Write-Host "    [!] $t" -ForegroundColor Yellow } }
function Ask($q) {
    if ($Yes) { return $true }
    $a = Read-Host "    $q [Y/n]"
    return ($a -eq '' -or $a -match '^(y|yes)$')
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
    foreach ($root in ($roots | Where-Object { $_ } | Select-Object -Unique)) {
        foreach ($rel in @('@dayone\cli\node_modules\@dayone\cli-win32-x64\dayone.exe', '@dayone\cli-win32-x64\dayone.exe')) {
            $p = Join-Path $root.Trim() $rel
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

# Pipes a SecureString's text straight into a program's stdin, then forgets it. Returns the exit code.
# (It must pipe into the program itself: text piped into a script block doesn't reach a program inside it.)
function Send-Secret([System.Security.SecureString] $Secret, [string] $Exe, [string[]] $ExeArgs) {
    $OutputEncoding = New-Object Text.UTF8Encoding $false   # keep non-ASCII characters intact (PowerShell 5.1)
    $text = (New-Object System.Net.NetworkCredential('', $Secret)).Password
    try { return (Invoke-Native -Quiet { $text | & $Exe @ExeArgs }) }
    finally { $text = $null; $Secret.Dispose() }
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
            $who = 'Signed in'
            $user = (ConvertFrom-JsonOutput $script:NativeOutput).user
            if ($user.display_name) { $who += " as $($user.display_name)" }
            if ($user.feature_bundle.bundle_name) { $who += " ($((Get-Culture).TextInfo.ToTitleCase($user.feature_bundle.bundle_name)))" }
            Ok $who
            # Only ask for the encryption key if this account uses end-to-end encryption.
            if (-not $user -or $user.key) {
                $key = Read-Host '    Encryption key (D1-..., or press Enter to skip)' -AsSecureString
            } else { $key = New-Object System.Security.SecureString }
            if ($key.Length -gt 0) {
                if ((Send-Secret $key $DayOneExe @('auth', 'key-set', '--key-stdin')) -eq 0) { Ok 'Encryption key saved' }
                else { Warn 'That key was not accepted. Add it later with: dayone auth key-set' }
            }
            return $true
        }
        Warn 'Wrong email or password. (Sign in with Google or Apple? Set a password first at dayone.me.)'
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

Write-Host ''
if ($Fancy) { Write-Host "  $($Icon.book) Day One MCP  " -ForegroundColor Magenta -NoNewline; Write-Host "by kachihro $($Icon.heart)" -ForegroundColor DarkGray }
else        { Write-Host '  Day One MCP  -  by kachihro' -ForegroundColor Magenta }
Write-Host '  github.com/kachihro/dayone-mcp' -ForegroundColor DarkGray

# ---------------------------------------------------------------------------------------------- uninstall
if ($Uninstall) {
    Step broom 'Uninstalling'
    if (-not $SkipClaudeCode -and (Get-Command claude -ErrorAction SilentlyContinue)) {
        Invoke-Native -Quiet { claude plugin uninstall "$PluginId" } | Out-Null
        Invoke-Native -Quiet { claude plugin marketplace remove $MarketplaceName } | Out-Null
        Invoke-Native -Quiet { claude mcp remove --scope user $ServerName } | Out-Null
        Ok 'Removed from Claude Code'
    }
    $cfg = Get-DesktopConfigPath
    if ($cfg -and (Test-Path $cfg)) {
        Update-DesktopConfig $cfg { param($s) $s.Remove($ServerName) }
        Ok 'Removed from Claude Desktop'
    }
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; Ok 'Removed the server' }
    Info 'The Day One CLI is still installed (remove it with: npm uninstall -g @dayone/cli)'
    Write-Host ''
    return
}

if ($env:PROCESSOR_ARCHITECTURE -notin @('AMD64', 'ARM64')) {
    throw 'dayone-mcp needs 64-bit Windows.'
}

# ---------------------------------------------------------------------------------------------- 1. Node.js + Day One CLI
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
Ok "Node.js $(& node --version)"

$dayoneExe = Find-DayOneExe
if (-not $dayoneExe) {
    if (-not (Ask 'Install the Day One CLI?')) { throw 'The Day One CLI is required.' }
    Info 'Installing the Day One CLI...'
    if ((Invoke-Native { npm install -g '@dayone/cli@latest' }) -ne 0) { throw 'Installing the Day One CLI failed (see above).' }
    Refresh-Path
    $dayoneExe = Find-DayOneExe
    if (-not $dayoneExe) { throw 'Installed the Day One CLI, but could not find dayone.exe. Please open an issue on GitHub.' }
}
Ok 'Day One CLI'

# ---------------------------------------------------------------------------------------------- 2. Sign in
$journals = Get-JournalCount $dayoneExe
# Signing in needs a person at the keyboard, so skip it when running unattended (-Yes).
if ($journals -eq 0 -and -not $Yes) {
    Step key 'Sign in to Day One'
    if (Connect-DayOne $dayoneExe) {
        Info 'Downloading your journals...'
        Invoke-Native -Quiet { & $dayoneExe sync } | Out-Null
        $journals = Get-JournalCount $dayoneExe
    }
}
if ($journals -gt 0) { Ok (Format-Journals (Get-Journals $dayoneExe)) }
else { Warn 'No journals yet. Run this installer again to sign in.' }

# ---------------------------------------------------------------------------------------------- 3. dayone-mcp
Step rocket 'Installing Day One MCP'
$localExe = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'DayOneMcp.exe' } else { $null }
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

if ($localExe -and (Test-Path $localExe)) {
    Copy-Item $localExe $ExePath -Force
} else {
    $url = if ($env:DAYONE_MCP_URL) { $env:DAYONE_MCP_URL }   # for forks and testing
           elseif ($Version) { "https://github.com/$Repo/releases/download/$Version/dayone-mcp-win-x64.zip" }
           else              { "https://github.com/$Repo/releases/latest/download/dayone-mcp-win-x64.zip" }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dayone-mcp-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp 'dayone-mcp.zip') -UseBasicParsing
        Expand-Archive (Join-Path $tmp 'dayone-mcp.zip') -DestinationPath $tmp -Force
        # Stop a running copy (e.g. Claude Desktop has it open) so the file can be replaced.
        Get-Process DayOneMcp -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $ExePath } | Stop-Process -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path $tmp 'DayOneMcp.exe') $ExePath -Force
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Unblock-File $ExePath -ErrorAction SilentlyContinue
[IO.File]::WriteAllText((Join-Path $InstallDir 'dayone-cli-path.txt'), $dayoneExe, (New-Object Text.UTF8Encoding $false))
Ok "$(& $ExePath --version)"

# Only mention the health check if something is actually wrong (no journals was already reported).
$check = & $ExePath --check
if ($LASTEXITCODE -eq 1) { Warn $check }

# ---------------------------------------------------------------------------------------------- 4. Claude
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
        Update-DesktopConfig $cfg { param($s) $s[$ServerName] = [ordered]@{ command = $ExePath; args = @() } }
        Ok 'Connected'
        $registered += 'Claude Desktop'
    } else {
        Info 'Not installed. Run this installer again after installing it.'
    }
}

# ---------------------------------------------------------------------------------------------- done
Write-Host ''
if ($Fancy) { Write-Host "$($Icon.party) All done!" -ForegroundColor Green } else { Write-Host '  All done!' -ForegroundColor Green }
$arrow = if ($Fancy) { "   $($Icon.arrow)" } else { '    -' }
if ($registered -contains 'Claude Desktop') { Write-Host "$arrow Claude Desktop: quit it fully (tray icon > Quit), then reopen" }
if ($registered -contains 'Claude Code')    { Write-Host "$arrow Claude Code: start a new session and try /dayone:on-this-day" }
Write-Host ''
if ($Fancy) { Write-Host "   $($Icon.coffee) Enjoying it? ko-fi.com/kachihro" -ForegroundColor DarkGray }
Write-Host ''
