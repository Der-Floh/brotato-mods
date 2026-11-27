<#
.SYNOPSIS
Ends a test session when its game closes. 'harness.ps1 start' runs it in a hidden window; see Wait-HarnessSessionEnd in Harness.psm1. Errors go to run/session-watcher.log, and the session then stays recorded until 'harness.ps1 stop'.
#>
param([Parameter(Mandatory)][int]$ProcessId)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Harness.psm1') -Force
    Wait-HarnessSessionEnd -ProcessId $ProcessId
}
catch {
    "$(Get-Date -Format s) $($_.Exception.Message)" | Add-Content -LiteralPath (Join-Path $PSScriptRoot 'run\session-watcher.log')
}
