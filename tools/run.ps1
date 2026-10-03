[CmdletBinding()]
param([switch]$ImportOnly, [string]$GodotPath)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $root 'game'
$godot = if ($GodotPath) { $GodotPath } elseif ($env:GODOT_EXE) { $env:GODOT_EXE } else { Join-Path $root '.tools/godot/godot.exe' }
$logs = Join-Path $root 'generated/validation'
if (-not (Test-Path -LiteralPath $godot)) {
    $taskGodotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($taskGodotCommand) { $godot = $taskGodotCommand.Source }
    else { throw 'Instala Godot y usa -GodotPath C:\ruta\Godot.exe, GODOT_EXE, o .tools/godot/godot.exe. Consulta README.md.' }
}
New-Item -ItemType Directory -Path $logs -Force | Out-Null

# Import new assets (sounds, models) and refresh the global GDScript class
# registry; --import waits until every resource is imported before quitting.
$stdout = Join-Path $logs 'launch_import.out.log'
$stderr = Join-Path $logs 'launch_import.err.log'
$import = Start-Process -FilePath $godot -ArgumentList @('--headless', '--import', '--path', ('"' + $gamePath + '"')) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$errors = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
if ($import.ExitCode -ne 0 -or $errors -match '(?m)^(SCRIPT ERROR:|ERROR:)') {
    throw "Godot import failed; see $stdout and $stderr"
}

if ($ImportOnly) { Write-Host 'GODOT IMPORT PASS'; return }
Start-Process -FilePath $godot -ArgumentList @('--path', ('"' + $gamePath + '"')) -WindowStyle Hidden
