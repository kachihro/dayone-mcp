<#
.SYNOPSIS
    Removes Day One MCP: the server, the Claude Code plugin and the Claude Desktop connection.

.DESCRIPTION
    Then asks whether to also sign out and remove the Day One CLI and its downloaded copy of your
    journals, for a completely fresh start. Your journals always stay safe in your Day One account.

.EXAMPLE
    irm https://raw.githubusercontent.com/kachihro/dayone-mcp/main/uninstall.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

# Use the installer next to this file if there is one (a cloned repo), otherwise the latest from GitHub.
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'install.ps1' } else { $null }
if ($local -and (Test-Path $local)) {
    & $local -Uninstall
} else {
    $url = if ($env:DAYONE_MCP_INSTALLER_URL) { $env:DAYONE_MCP_INSTALLER_URL }   # for forks and testing
           else { 'https://raw.githubusercontent.com/kachihro/dayone-mcp/main/install.ps1' }
    & ([scriptblock]::Create((Invoke-RestMethod -Uri $url -UseBasicParsing))) -Uninstall
}
