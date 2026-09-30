[CmdletBinding()]
param([switch]$Capture, [switch]$Perf)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $root 'game'
$godot = Join-Path $root '.tools/godot/godot.exe'
$logs = Join-Path $root 'generated/validation'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
Start-Transcript -Path (Join-Path $logs 'validate.transcript.log') -Force | Out-Null
trap { Stop-Transcript | Out-Null; break }

& (Join-Path $PSScriptRoot 'bootstrap.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Bootstrap check failed.' }
& py -3.13 -m unittest discover -s (Join-Path $root 'tests') -v
if ($LASTEXITCODE -ne 0) { throw 'Python tests failed.' }
& py -3.13 (Join-Path $PSScriptRoot 'verify_assets.py')
if ($LASTEXITCODE -ne 0) { throw 'Asset verification failed.' }
& py -3.13 (Join-Path $PSScriptRoot 'third_party/import_assets.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Third-party asset verification failed.' }
& py -3.13 (Join-Path $PSScriptRoot 'third_party/palm_bark.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Palm bark verification failed.' }
& py -3.13 (Join-Path $PSScriptRoot 'third_party/clean_asphalt.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Clean asphalt verification failed.' }
& py -3.13 (Join-Path $PSScriptRoot 'world/check_clearance.py')
if ($LASTEXITCODE -ne 0) { throw 'Driveable road clearance failed.' }

function Invoke-Godot([string]$Name, [string[]]$Arguments) {
    $stdout = Join-Path $logs "$Name.out.log"
    $stderr = Join-Path $logs "$Name.err.log"
    $process = Start-Process -FilePath $godot -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $outText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
    $errText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
    if ($outText) { Write-Host $outText.TrimEnd() }
    if ($errText) { Write-Host $errText.TrimEnd() }
    if ($process.ExitCode -ne 0 -or $errText -match '(?m)^(SCRIPT ERROR:|ERROR:)') {
        throw "Godot $Name failed; see $stdout and $stderr"
    }
}

Invoke-Godot 'import' @('--headless', '--editor', '--path', ('"' + $gamePath + '"'), '--quit')
Invoke-Godot 'smoke' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/smoke.gd')
Invoke-Godot 'damage' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/damage_test.gd')
Invoke-Godot 'jaime_mission' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/jaime_mission.gd')
Invoke-Godot 'missions' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/missions.gd')
Invoke-Godot 'weapons' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/weapons.gd')
Invoke-Godot 'slope_buildings' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/slope_buildings.gd')
Invoke-Godot 'water_and_dressing' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/water_and_dressing.gd')
Invoke-Godot 'civilian_life' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/civilian_life.gd')
Invoke-Godot 'workshop_interior' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/workshop_interior.gd')
Invoke-Godot 'venues' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/venues.gd')
Invoke-Godot 'traffic' @('--headless', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/traffic_soak.gd')
Invoke-Godot 'route' @('--headless', '--fixed-fps', '60', '--path', ('"' + $gamePath + '"'), '--script', 'res://tests/route_trial.gd')
if ($Capture) {
    Invoke-Godot 'capture' @('--path', ('"' + $gamePath + '"'), '--script', 'res://tests/capture.gd')
}
if ($Perf) {
    # Fullscreen (native resolution) on the real GPU: the full El Recado route with police
    # pursuit, recording frame times per gameplay context into generated/playtests/.
    # The second pass disables vsync to measure headroom above the refresh rate.
    Invoke-Godot 'perf_route' @('--path', ('"' + $gamePath + '"'), '--script', 'res://tests/route_trial.gd', '--', '--perf')
    Invoke-Godot 'perf_route_uncapped' @('--path', ('"' + $gamePath + '"'), '--script', 'res://tests/route_trial.gd', '--', '--perf', '--uncapped')
}
Write-Host 'VALIDATION PASS'
Stop-Transcript | Out-Null
