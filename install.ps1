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

function Step($t)  { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "    [ok] $t" -ForegroundColor Green }
function Info($t)  { Write-Host "    $t" }
function Warn($t)  { Write-Host "    [!] $t" -ForegroundColor Yellow }
function Ask($q) {
    if ($Yes) { return $true }
    $a = Read-Host "    $q [Y/n]"
    return ($a -eq '' -or $a -match '^(y|yes)$')
}
# Runs a native command without letting its stderr output become a terminating error
# (Windows PowerShell 5.1 does that when $ErrorActionPreference is 'Stop'). Returns the exit code.
function Invoke-Native([scriptblock] $Command, [switch] $Quiet) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) { & $Command 2>&1 | Out-Null } else { & $Command 2>&1 | ForEach-Object { Write-Host "    $_" } }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
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

function Get-JournalCount([string] $DayOneExe) {
    $ErrorActionPreference = 'Continue'   # local to this function: stderr warnings must not abort the read
    try { return [int]((& $DayOneExe list journals 2>$null | Out-String | ConvertFrom-Json).count) } catch { return 0 }
}

Write-Host ''
Write-Host '  Day One MCP for Claude  -  https://github.com/kachihro/dayone-mcp' -ForegroundColor Magenta

# ---------------------------------------------------------------------------------------------- uninstall
if ($Uninstall) {
    Step 'Uninstalling dayone-mcp'
    if (-not $SkipClaudeCode -and (Get-Command claude -ErrorAction SilentlyContinue)) {
        Invoke-Native -Quiet { claude plugin uninstall "$PluginId" } | Out-Null
        Invoke-Native -Quiet { claude plugin marketplace remove $MarketplaceName } | Out-Null
        Invoke-Native -Quiet { claude mcp remove --scope user $ServerName } | Out-Null
        Ok 'Removed from Claude Code'
    }
    $cfg = Get-DesktopConfigPath
    if ($cfg -and (Test-Path $cfg)) {
        Update-DesktopConfig $cfg { param($s) $s.Remove($ServerName) }
        Ok 'Removed from Claude Desktop (restart it to finish)'
    }
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; Ok "Deleted $InstallDir" }
    Info 'The Day One CLI was left installed. Remove it with: npm uninstall -g @dayone/cli'
    return
}

if ($env:PROCESSOR_ARCHITECTURE -notin @('AMD64', 'ARM64')) {
    throw 'dayone-mcp needs 64-bit Windows.'
}

# ---------------------------------------------------------------------------------------------- 1. Node.js
Step 'Checking Node.js (needed by the Day One CLI)'
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Warn 'Node.js is not installed.'
    if ((Get-Command winget -ErrorAction SilentlyContinue) -and (Ask 'Install Node.js LTS now with winget?')) {
        winget install --id OpenJS.NodeJS.LTS --exact --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'Please install Node.js LTS from https://nodejs.org, open a new PowerShell window, and run this again.'
    }
}
Ok "Node.js $(& node --version)"

# ---------------------------------------------------------------------------------------------- 2. Day One CLI
Step 'Checking the Day One CLI'
$dayoneExe = Find-DayOneExe
if (-not $dayoneExe) {
    if (-not (Ask 'Install the official Day One CLI (npm install -g @dayone/cli)?')) { throw 'The Day One CLI is required.' }
    & npm install -g '@dayone/cli@latest'
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed. See the messages above.' }
    Refresh-Path
    $dayoneExe = Find-DayOneExe
    if (-not $dayoneExe) { throw 'Installed @dayone/cli, but could not find dayone.exe. Please open an issue on GitHub.' }
}
Ok "Day One CLI: $dayoneExe"

$journals = Get-JournalCount $dayoneExe
if ($journals -eq 0) {
    Warn 'No journals found yet. You need to sign in to Day One and download your journals.'
    # Signing in is interactive (email + password), so skip it when running unattended (-Yes).
    if (-not $Yes -and (Ask 'Sign in now? (runs "dayone setup", then "dayone sync")')) {
        & $dayoneExe setup
        Info 'Downloading your journals (the first sync can take a few minutes)...'
        & $dayoneExe sync
        $journals = Get-JournalCount $dayoneExe
    }
}
if ($journals -gt 0) { Ok "$journals journal(s) available" }
else { Warn 'Still no journals. Run "dayone setup" and "dayone sync" later (and "dayone auth key-set" if your journals are encrypted).' }

# ---------------------------------------------------------------------------------------------- 3. dayone-mcp
Step 'Installing the dayone-mcp server'
$localExe = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'DayOneMcp.exe' } else { $null }
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

if ($localExe -and (Test-Path $localExe)) {
    Copy-Item $localExe $ExePath -Force
    Ok 'Copied DayOneMcp.exe from this folder'
} else {
    $url = if ($env:DAYONE_MCP_URL) { $env:DAYONE_MCP_URL }   # for forks and testing
           elseif ($Version) { "https://github.com/$Repo/releases/download/$Version/dayone-mcp-win-x64.zip" }
           else              { "https://github.com/$Repo/releases/latest/download/dayone-mcp-win-x64.zip" }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dayone-mcp-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Info "Downloading $url"
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
Ok "$(& $ExePath --version) installed to $InstallDir"

$check = & $ExePath --check
if ($LASTEXITCODE -eq 0) { Ok $check } else { Warn $check }

# ---------------------------------------------------------------------------------------------- 4. Claude
$registered = @()

if (-not $SkipClaudeCode) {
    Step 'Connecting to Claude Code'
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        # The Claude Code plugin brings the MCP server plus /dayone:* commands. It replaces any
        # older "claude mcp add" registration, so remove that first to avoid duplicate tools.
        Invoke-Native -Quiet { claude mcp remove --scope user $ServerName } | Out-Null
        $code = Invoke-Native { claude plugin marketplace add $MarketplaceSource }
        if ($code -eq 0) {
            # Refresh the marketplace so a re-run picks up new plugin versions, then install (or update).
            Invoke-Native -Quiet { claude plugin marketplace update $MarketplaceName } | Out-Null
            $code = Invoke-Native { claude plugin install "$PluginId" }
            if ($code -eq 0) { Invoke-Native { claude plugin update "$PluginId" } | Out-Null }
        }
        if ($code -eq 0) {
            Ok 'Installed the Day One plugin for Claude Code'
            $registered += 'Claude Code'
        } else {
            Warn "Couldn't install the plugin, so adding the MCP server directly instead."
            $code = Invoke-Native { claude mcp add --scope user --transport stdio $ServerName -- $ExePath }
            if ($code -eq 0) { Ok 'Added for all your projects (user scope)'; $registered += 'Claude Code' }
            else { Warn "That didn't work either. In Claude Code, run: /plugin install dayone --marketplace $Repo" }
        }
    } else {
        Info "Claude Code isn't installed (or not on PATH). Later, in Claude Code run:"
        Info "  /plugin install dayone --marketplace $Repo"
    }
}

if (-not $SkipClaudeDesktop) {
    Step 'Connecting to Claude Desktop'
    $cfg = Get-DesktopConfigPath
    if ($cfg) {
        Update-DesktopConfig $cfg { param($s) $s[$ServerName] = [ordered]@{ command = $ExePath; args = @() } }
        Ok "Updated $cfg (backup saved as .bak)"
        $registered += 'Claude Desktop'
    } else {
        Info "Claude Desktop isn't installed. Run this installer again after installing it."
    }
}

# ---------------------------------------------------------------------------------------------- done
Write-Host ''
Write-Host '  All done!' -ForegroundColor Green
if ($registered -contains 'Claude Desktop') {
    Write-Host '  - Claude Desktop: fully quit it (right-click the tray icon > Quit) and reopen it.'
}
if ($registered -contains 'Claude Code') {
    Write-Host '  - Claude Code: start a new session and try /dayone:on-this-day (or /dayone:setup to check everything).'
}
Write-Host "  Then ask: 'What did I write on this day in previous years?'"
Write-Host ''
