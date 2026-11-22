<#
.SYNOPSIS
    Sets Day One MCP up for you: sign in to Day One, add your encryption key, and sync your journals.

.DESCRIPTION
    Runs Part 2 of the installer ("Setting it up for you") without reinstalling anything. Use it to:
      - sign in, or switch to a different Day One account
      - add your encryption key (for end-to-end encrypted journals)
      - download your latest entries

    Install first with install.ps1 if you haven't already.

.EXAMPLE
    irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/configure.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

# Use the installer next to this file if there is one (a cloned repo), otherwise the latest from GitHub.
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'install.ps1' } else { $null }
if ($local -and (Test-Path $local)) {
    & $local -Configure
} else {
    $url = if ($env:DAYONE_MCP_INSTALLER_URL) { $env:DAYONE_MCP_INSTALLER_URL }   # for forks and testing
           else { 'https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1' }
    & ([scriptblock]::Create((Invoke-RestMethod -Uri $url -UseBasicParsing))) -Configure
}
