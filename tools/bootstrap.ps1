[CmdletBinding()]
param(
    [string]$GodotPath = '',
    [string]$BlenderPath = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$rows = [System.Collections.Generic.List[object]]::new()
$failed = $false

function Add-Check([string]$Name, [string]$Required, [string]$Found, [bool]$Ok, [string]$Action) {
    $script:rows.Add([pscustomobject]@{
        Dependency = $Name
        Required = $Required
        Detected = $Found
        Status = if ($Ok) { 'OK' } else { 'MISSING / WRONG VERSION' }
        Action = $Action
    })
    if (-not $Ok) { $script:failed = $true }
}

function Find-Executable([string]$Override, [string[]]$Candidates, [string]$CommandName) {
    if ($Override) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) { throw "Executable override not found: $Override" }
        return (Resolve-Path -LiteralPath $Override).Path
    }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return ''
}

function Read-Version([string]$Executable, [string[]]$Arguments) {
    if (-not $Executable) { return 'not found' }
    try {
        $output = & $Executable @Arguments 2>&1 | Select-Object -First 1
        return [string]$output
    } catch {
        return "failed: $($_.Exception.Message)"
    }
}

$git = Find-Executable '' @() 'git'
$gitVersion = Read-Version $git @('--version')
Add-Check 'Git' 'available' "$gitVersion [$git]" ($gitVersion -match '^git version ') 'Install Git for Windows.'

$lfs = Find-Executable '' @() 'git-lfs'
$lfsVersion = Read-Version $lfs @('version')
Add-Check 'Git LFS' 'available' "$lfsVersion [$lfs]" ($lfsVersion -match '^git-lfs/') 'Install Git LFS.'

$python = Find-Executable '' @() 'py'
if ($python) {
    $pythonVersion = Read-Version $python @('-3.13', '--version')
} else {
    $python = Find-Executable '' @() 'python'
    $pythonVersion = Read-Version $python @('--version')
}
Add-Check 'Python' '3.11+' "$pythonVersion [$python]" ($pythonVersion -match '^Python 3\.(1[1-9]|[2-9][0-9])\.') 'Install Python 3.11 or newer.'

$uv = Find-Executable '' @() 'uv'
$uvVersion = Read-Version $uv @('--version')
Add-Check 'uv' 'available' "$uvVersion [$uv]" ($uvVersion -match '^uv ') 'Install uv.'

$godotCandidates = @(
    (Join-Path $root '.tools/godot/godot.exe'),
    (Join-Path $root '.tools/godot/Godot_v4.7.2-stable_win64.exe')
)
$godot = Find-Executable $GodotPath $godotCandidates 'godot'
$godotVersion = Read-Version $godot @('--version')
Add-Check 'Godot' '4.7.x stable' "$godotVersion [$godot]" ($godotVersion -match '^4\.7(?:\.[0-9]+)?\.stable') 'Extract the standard Windows x64 build into .tools/godot; see SETUP_STATUS.md.'

$blenderCandidates = @(
    (Join-Path $root '.tools/blender/blender.exe'),
    (Join-Path $root '.tools/blender/blender-5.2.2-windows-x64/blender.exe'),
    'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
)
$blender = Find-Executable $BlenderPath $blenderCandidates 'blender'
$blenderVersion = Read-Version $blender @('--background', '--version')
Add-Check 'Blender' '5.2.x LTS' "$blenderVersion [$blender]" ($blenderVersion -match '^Blender 5\.2\.[0-9]+') 'Extract Blender 5.2 LTS into .tools/blender; see SETUP_STATUS.md.'

$rows | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host
if ($failed) {
    Write-Error 'Environment check failed. Follow SETUP_STATUS.md and rerun tools/bootstrap.ps1.'
    exit 1
}
Write-Host 'Environment ready for Godot import and Blender generation.'
exit 0
