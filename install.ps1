# AP (Armor Piercing) -- Grok Build plugin installer
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -DryRun
#
# Installs this folder as a user-scope Grok plugin under ~/.grok, trusts it, and
# enables it. Both Grok Build Desktop and the Grok CLI read the same ~/.grok tree,
# so one install covers both.

param(
  [string]$GrokExe = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$pluginName = "ap"

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
if (-not $grok) {
  Write-Host "Could not find the grok executable." -ForegroundColor Red
  Write-Host "Pass it explicitly:  install.ps1 -GrokExe 'C:\path\to\grok.exe'"
  exit 1
}

Write-Host "grok      : $grok"
Write-Host "plugin    : $pluginName"
Write-Host "source    : $here"
& $grok --version

if (-not (Test-Path (Join-Path $here "plugin.json"))) {
  Write-Host "plugin.json not found in $here -- run this from the plugin folder." -ForegroundColor Red
  exit 1
}

# Node is required: the hooks are Node scripts.
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Host "Node.js not found on PATH. The hooks are Node scripts and will not run without it." -ForegroundColor Red
  Write-Host "Install Node.js, then re-run this script."
  exit 1
}
Write-Host "node      : $($node.Source)"

if ($DryRun) {
  Write-Host "`n[DryRun] would run:" -ForegroundColor Yellow
  Write-Host "  `"$grok`" plugin validate `"$here`""
  Write-Host "  `"$grok`" plugin install `"$here`" --trust"
  Write-Host "  `"$grok`" plugin enable $pluginName"
  exit 0
}

Write-Host "`n[1/3] validating manifest ..."
& $grok plugin validate $here
if ($LASTEXITCODE -ne 0) { throw "manifest validation failed (exit $LASTEXITCODE)" }

Write-Host "`n[2/3] installing ..."
& $grok plugin install $here --trust
if ($LASTEXITCODE -ne 0) { throw "plugin install failed (exit $LASTEXITCODE)" }

Write-Host "`n[3/3] enabling ..."
& $grok plugin enable $pluginName
if ($LASTEXITCODE -ne 0) { throw "plugin enable failed (exit $LASTEXITCODE)" }

Write-Host "`nInstalled plugins:" -ForegroundColor Green
& $grok plugin list

Write-Host @"

Done. Next steps:
  1. Fully quit Grok Build Desktop, including the tray icon, then reopen it.
     The CLI needs no restart beyond a new session.
  2. Start a NEW conversation. The frame is assembled at session start, so an
     already-open session will not pick it up.
  3. Verify: send the wake word  AP  and expect exactly
         Sir I'm here，干什么你直说。
  4. Inspect what the hooks delivered:
         Get-ChildItem "`$env:USERPROFILE\.grok\plugin-data" -Recurse -Filter runtime.log |
           ForEach-Object { Get-Content `$_.FullName -Tail 20 }

Uninstall:  powershell -ExecutionPolicy Bypass -File uninstall.ps1
"@
