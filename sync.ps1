# AP (Armor Piercing) -- sync source edits into the installed copy
#
# A plugin installed from a local path is discovered from the installed snapshot at
# <GROK_HOME>/installed-plugins/<id>. Editing this source folder alone does not change
# what the host loads. Run this after every edit.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File sync.ps1

param(
  [string]$GrokExe = "",
  [string]$Id = ""
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$pluginName = "ap"
$grokHome = Join-Path $env:USERPROFILE ".grok"
$installedRoot = Join-Path $grokHome "installed-plugins"

function Find-Grok {
  param([string]$Explicit)
  if ($Explicit -and (Test-Path $Explicit)) { return (Resolve-Path $Explicit).Path }
  $cmd = Get-Command grok -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $guess = Join-Path $env:USERPROFILE ".grok\downloads\grok-windows-x86_64.exe"
  if (Test-Path $guess) { return $guess }
  return $null
}

$grok = Find-Grok $GrokExe

if (-not $Id) {
  if (-not $grok) {
    Write-Host "Cannot list plugins without the grok executable. Pass -GrokExe or -Id." -ForegroundColor Red
    exit 1
  }
  $listOut = & $grok plugin list 2>&1 | Out-String
  foreach ($line in ($listOut -split "`r?`n")) {
    if ($line -match '^\s*(?<id>[^\s:]+)\s*:\s*(?<name>[^\s\[]+)\s*\[' ) {
      if ($Matches.name -eq $pluginName) { $Id = $Matches.id; break }
    }
  }
}

if (-not $Id) {
  Write-Host "Plugin '$pluginName' is not installed. Run install.ps1 first." -ForegroundColor Red
  exit 1
}

$target = Join-Path $installedRoot $Id
if (-not (Test-Path $target)) {
  Write-Host "Installed copy not found at $target" -ForegroundColor Red
  exit 1
}

Write-Host "source : $here"
Write-Host "target : $target"

# Syntax gate before touching the live copy.
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
  & $node.Source --check (Join-Path $here "hooks\hook.js")
  if ($LASTEXITCODE -ne 0) { throw "hook.js failed syntax check; nothing synced" }
}

$files = @(
  "plugin.json",
  "prompts\ap.md",
  "hooks\hook.js",
  "hooks\hooks.json",
  "skills\ap\SKILL.md"
)

foreach ($rel in $files) {
  $s = Join-Path $here $rel
  $d = Join-Path $target $rel
  if (-not (Test-Path $s)) { Write-Host "skip (missing in source): $rel" -ForegroundColor Yellow; continue }
  New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null
  Copy-Item $s $d -Force
  Write-Host "synced  $rel"
}

Write-Host "`nSynced. Start a new session (a running session keeps the hooks it loaded)." -ForegroundColor Green
