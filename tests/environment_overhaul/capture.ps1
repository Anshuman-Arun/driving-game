# Run from a real graphical Windows desktop, with a console Godot executable.
param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Output,
    [ValidateSet("baseline","candidate")][string]$Mode="baseline",
    [ValidateSet("cedar","valley","alder","ridge","eastwater")][string]$Site="cedar",
    [ValidateSet("stationary","offroad","manual","route")][string]$Scenario="stationary",
    [ValidateSet("medium","high","low")][string]$Preset="medium",
    [string]$Features="",
    [ValidateRange(60,600)][int]$Seconds=60,
    [ValidateRange(5,120)][int]$Warmup=15,
    [ValidateRange(1,60.8)][double]$SpeedMps=22.35
)
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Godot = (Resolve-Path $Godot).Path
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path $Output) { throw "Use a new output directory: $Output" }
if ($Output.StartsWith($Root + [System.IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Capture outside the repository to avoid import and accidental commits"
}
Push-Location $Root
try {
    $commit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Git revision unavailable" }
    $dirty = git status --porcelain --untracked-files=no
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw "Tracked changes present; commit first for reproducibility" }
    $version = & $Godot --headless --version
    if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^4\.7\.2\.stable') { throw "Use pinned Godot 4.7.2 stable" }
    New-Item -ItemType Directory -Path $Output | Out-Null
    $speed = $SpeedMps.ToString([Globalization.CultureInfo]::InvariantCulture)
    $engineArgs = @("--path",$Root,"--rendering-method","forward_plus","--resolution","1920x1080",
        "--script","res://tests/environment_overhaul/capture.gd","--",
        "--out=$Output","--mode=$Mode","--site=$Site","--scenario=$Scenario","--preset=$Preset",
        "--features=$Features","--seconds=$Seconds","--warmup=$Warmup","--speed-mps=$speed","--commit=$commit")
    & $Godot @engineArgs 2>&1 | Tee-Object -FilePath (Join-Path $Output "console.log")
    $status = $LASTEXITCODE
    if ($status -ne 0 -or (Select-String -Path (Join-Path $Output "console.log") -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|Shader error')) { throw "Capture failed; inspect console.log" }
    if (!(Test-Path (Join-Path $Output "meta.json")) -or !(Test-Path (Join-Path $Output "frames.csv"))) { throw "Capture incomplete" }
    Write-Host "Capture saved: $Output"
} finally { Pop-Location }
