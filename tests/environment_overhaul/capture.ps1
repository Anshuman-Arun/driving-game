# Run from a real graphical Windows desktop, with a console Godot executable.
param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Output,
    [ValidateSet("baseline","candidate")][string]$Mode="baseline",
    [ValidateSet("cedar","valley","alder","ridge","eastwater")][string]$Site="cedar",
    [ValidateSet("stationary","offroad","manual","route")][string]$Scenario="stationary",
    [ValidateSet("medium","high","low")][string]$Preset="medium",
    [string]$Features="",
    [string]$OptionsFile="",
    [switch]$Interaction,
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
    $dirty = git status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw "Tracked or untracked changes present; commit first for reproducibility" }
    $version = & $Godot --headless --version
    if ($LASTEXITCODE -ne 0 -or "$version" -notmatch '^4\.7\.2\.stable') { throw "Use pinned Godot 4.7.2 stable" }
    New-Item -ItemType Directory -Path $Output | Out-Null
    $speed = $SpeedMps.ToString([Globalization.CultureInfo]::InvariantCulture)
    $engineArgs = @("--path",$Root,"--rendering-method","forward_plus","--resolution","1920x1080",
        "--script","res://tests/environment_overhaul/capture.gd","--",
        "--out=$Output","--mode=$Mode","--site=$Site","--scenario=$Scenario","--preset=$Preset",
        "--features=$Features","--seconds=$Seconds","--warmup=$Warmup","--speed-mps=$speed","--commit=$commit")
    if ($OptionsFile) { $engineArgs += "--options=$((Resolve-Path $OptionsFile).Path)" }
    if ($Interaction) { $engineArgs += "--interaction=on" }
    # Bounded wait, including scene boot/import stalls or a paused frame signal.
    # Windows paths cannot contain quotes; quote each arg, doubling trailing
    # backslashes before its closing quote per Win32 command-line parsing.
    $quoted = $engineArgs | ForEach-Object { '"' + ($_ -replace '(\\+)
    if ($status -ne 0 -or (Select-String -Path (Join-Path $Output "console.log") -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|Shader error')) { throw "Capture failed; inspect console.log" }
    if (!(Test-Path (Join-Path $Output "meta.json")) -or !(Test-Path (Join-Path $Output "frames.csv"))) { throw "Capture incomplete" }
    $metaPath=Join-Path $Output "meta.json"
    $metadata=Get-Content $metaPath -Raw | ConvertFrom-Json
    if ($metadata.complete -ne $true) { throw "Incomplete capture metadata" }
    # Driver data fallback is only accepted when exactly one Windows adapter
    # matches Godot's actual GPU name. Do not choose the first hybrid adapter.
    try {
        $adapters=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,PNPDeviceID)
        $metadata | Add-Member -NotePropertyName windows_adapters -NotePropertyValue $adapters -Force
        if (!$metadata.driver -or $metadata.driver -eq "unavailable") {
            $match=@($adapters | Where-Object { $_.Name -eq $metadata.gpu })
            if ($match.Count -eq 1 -and $match[0].DriverVersion) {
                $metadata.driver=@("Windows CIM exact adapter name",$match[0].DriverVersion)
            }
        }
    } catch { Write-Warning "Windows adapter metadata unavailable" }
    [IO.File]::WriteAllText($metaPath,($metadata | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    Write-Host "Capture saved: $Output"
} finally { Pop-Location }
,'$1$1') + '"' }
    $stdout = Join-Path $Output "stdout.log"
    $stderr = Join-Path $Output "stderr.log"
    $process = Start-Process -FilePath $Godot -ArgumentList ($quoted -join ' ') -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $announced = $false
    try {
        while (!$process.WaitForExit(500)) {
            if (!$announced -and (Test-Path $stdout) -and (Select-String -Quiet -Path $stdout -Pattern 'CAPTURE START')) {
                Write-Host "CAPTURE START — manual scenario: drive now"
                $announced = $true
            }
            if ($timer.Elapsed.TotalSeconds -gt ($Seconds + $Warmup + 180)) {
                $process.Kill()
                throw "Capture timed out; inspect stdout.log and stderr.log"
            }
        }
        $status=$process.ExitCode
    } finally {
        if (!$process.HasExited) { $process.Kill() }
        $process.Dispose()
        @((Get-Content $stdout -ErrorAction SilentlyContinue),(Get-Content $stderr -ErrorAction SilentlyContinue)) | Set-Content (Join-Path $Output "console.log")
    }
    if ($status -ne 0 -or (Select-String -Path (Join-Path $Output "console.log") -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|Shader error')) { throw "Capture failed; inspect console.log" }
    if (!(Test-Path (Join-Path $Output "meta.json")) -or !(Test-Path (Join-Path $Output "frames.csv"))) { throw "Capture incomplete" }
    Write-Host "Capture saved: $Output"
} finally { Pop-Location }
