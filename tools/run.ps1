[CmdletBinding()]
param([switch]$ImportOnly)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $root 'game'
$godot = Join-Path $root '.tools/godot/godot.exe'
$logs = Join-Path $root 'generated/validation'
if (-not (Test-Path -LiteralPath $godot)) { throw "Godot executable missing: $godot" }
New-Item -ItemType Directory -Path $logs -Force | Out-Null

# Refresh Godot's global GDScript class registry after scripts are added or moved.
$stdout = Join-Path $logs 'launch_import.out.log'
$stderr = Join-Path $logs 'launch_import.err.log'
$import = Start-Process -FilePath $godot -ArgumentList @('--headless', '--editor', '--path', ('"' + $gamePath + '"'), '--quit') -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$errors = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
if ($import.ExitCode -ne 0 -or $errors -match '(?m)^(SCRIPT ERROR:|ERROR:)') {
    throw "Godot import failed; see $stdout and $stderr"
}

if ($ImportOnly) { Write-Host 'GODOT IMPORT PASS'; return }
Start-Process -FilePath $godot -ArgumentList @('--path', ('"' + $gamePath + '"'))
