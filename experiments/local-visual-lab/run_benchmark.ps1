param(
    [string]$GodotExe = "",
    [string]$Resolution = "1920x1080",
    [string[]]$Presets = @("Performance", "Balanced", "High"),
    [switch]$SkipHeadlessCheck
)

$ErrorActionPreference = "Stop"
$LabDir = $PSScriptRoot

if (-not $GodotExe) {
    $candidates = @(
        (Get-Command godot_console -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        (Get-Command godot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $GodotExe = $c
            break
        }
    }
}

if (-not $GodotExe -or -not (Test-Path $GodotExe)) {
    throw "Godot 4.7.2 executable not found. Pass -GodotExe <path>."
}

$env:APPDATA = Join-Path $LabDir ".godot\appdata"
$env:LOCALAPPDATA = Join-Path $LabDir ".godot\localappdata"
$BenchDir = Join-Path $LabDir "benchmarks"
$ShotDir = Join-Path $LabDir "screenshots"
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA, $BenchDir, $ShotDir | Out-Null

Write-Host "=== Aster Valley Local Visual Lab Benchmark ==="
Write-Host "Project:    $LabDir"
Write-Host "Resolution: $Resolution"
Write-Host "Presets:    $($Presets -join ', ')"

if (-not $SkipHeadlessCheck) {
    Write-Host "`n[1/2] Running headless editor import & parse check..."
    & $GodotExe --headless --path $LabDir --editor --quit
    if ($LASTEXITCODE -ne 0) {
        throw "Headless editor check failed with exit code $LASTEXITCODE"
    }
}

Write-Host "`n[2/2] Running live GPU benchmarks..."
foreach ($preset in $Presets) {
    $slug = $preset.ToLower()
    $outJson = Join-Path $BenchDir "$slug.json"
    Write-Host "`n--- Preset: $preset ($Resolution) ---"
    & $GodotExe --path $LabDir --resolution $Resolution -- --benchmark --preset=$preset --out=$outJson --screenshots=$ShotDir
    if ($LASTEXITCODE -ne 0) {
        throw "Benchmark failed for preset $preset (exit code $LASTEXITCODE)"
    }
}

Write-Host "`nAll benchmarks completed cleanly. Reports saved in $BenchDir"
