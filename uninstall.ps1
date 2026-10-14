# AP (Armor Piercing) -- Grok Build plugin uninstaller
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1 -PurgeData

param(
  [string]$GrokExe = "",
  [switch]$PurgeData
)

$ErrorActionPreference = "Stop"
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
  Write-Host "Could not find the grok executable. Pass -GrokExe." -ForegroundColor Red
  exit 1
}

# Resolve the installed plugin id. It is derived from the source path at install time
# and is therefore not stable across re-installs. Match the "id: name [kind: ...]"
# shape exactly so an unrelated plugin whose name merely contains "ap" cannot match.
$id = $null
$listOut = & $grok plugin list 2>&1 | Out-String
foreach ($line in ($listOut -split "`r?`n")) {
  if ($line -match '^\s*(?<id>[^\s:]+)\s*:\s*(?<name>[^\s\[]+)\s*\[' ) {
    if ($Matches.name -eq $pluginName) { $id = $Matches.id; break }
  }
}

if (-not $id) {
  Write-Host "Plugin '$pluginName' does not appear in 'grok plugin list'." -ForegroundColor Yellow
} else {
  Write-Host "uninstalling : $id"
  & $grok plugin uninstall $id --confirm
}

# Strip any leftover [plugins].enabled entry, and remove this plugin's rules directory
# from [paths] extra_rule_dirs. Written with .NET UTF-8 so config.toml keeps its bytes
# and BOM state -- PowerShell's Set-Content can mangle non-ASCII values elsewhere in
# the file (the model name, comments).
$cfg = Join-Path $env:USERPROFILE ".grok\config.toml"
$ruleDir = (Join-Path $PSScriptRoot "rules").Replace('\', '/')

if (Test-Path $cfg) {
  $text = [System.IO.File]::ReadAllText($cfg)
  $before = $text

  $text = $text -replace ('(?m)^\s*enabled\s*=\s*\[[^\]]*"' + [regex]::Escape($pluginName) + '"[^\]]*\]\s*\r?\n?'), ''

  # Drop our path from extra_rule_dirs. Handles both the single-entry and multi-entry
  # forms; if other directories remain, the key is rewritten with only those.
  $m = [regex]::Match($text, '(?m)^\s*extra_rule_dirs\s*=\s*\[(?<body>[^\]]*)\]\s*$')
  if ($m.Success) {
    $entries = @()
    foreach ($piece in ($m.Groups['body'].Value -split ',')) {
      $p = $piece.Trim().Trim('"')
      if ($p -and ($p.Replace('\', '/').TrimEnd('/') -ne $ruleDir.TrimEnd('/'))) { $entries += $p }
    }
    if ($entries.Count -eq 0) {
      $text = $text.Remove($m.Index, $m.Length)
      $text = $text -replace '(?m)^\s*\[paths\]\s*\r?\n?', ''
      Write-Host "removed [paths] extra_rule_dirs (it held only this plugin's rules)"
    } else {
      $repl = 'extra_rule_dirs = [' + (($entries | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']'
      $text = $text.Remove($m.Index, $m.Length).Insert($m.Index, $repl)
      Write-Host "kept $($entries.Count) other entry/entries in extra_rule_dirs"
    }
  }

  if ($text -ne $before) {
    [System.IO.File]::WriteAllText($cfg, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "cleaned config.toml"
  } else {
    Write-Host "no config.toml entry to clean"
  }
}

if ($PurgeData) {
  $root = Join-Path $env:USERPROFILE ".grok\plugin-data"
  if (Test-Path $root) {
    Get-ChildItem -Path $root -Recurse -Directory -Filter $pluginName -ErrorAction SilentlyContinue |
      ForEach-Object {
        Write-Host "purging data: $($_.FullName)"
        Remove-Item -Recurse -Force $_.FullName
      }
  }
}

Write-Host "`nUninstalled. Fully quit and reopen Grok Build Desktop for the change to take effect." -ForegroundColor Green
