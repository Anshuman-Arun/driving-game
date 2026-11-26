# Graphical Windows desktop launcher. PowerShell 5.1+; -SelfTest does not use Godot.
[CmdletBinding(DefaultParameterSetName="Capture")]
param(
    [Parameter(Mandatory=$true,ParameterSetName="Capture")][string]$Godot,
    [Parameter(Mandatory=$true,ParameterSetName="Capture")][string]$Output,
    [Parameter(Mandatory=$true,ParameterSetName="SelfTest")][switch]$SelfTest,
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

function ConvertTo-NativeArgument([AllowEmptyString()][string]$Value) {
    # All supported path/option values may contain spaces but not literal
    # quotes or line breaks. Double trailing slashes before closing quote.
    if ($Value -match '["\r\n]') { throw "Unsupported native argument" }
    return '"' + ($Value -replace '(\\+)$','$1$1') + '"'
}

function Join-NativeArguments([string[]]$Values) {
    return (($Values | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
}

function Assert-FeatureSelection([string]$CaptureMode,[string]$Flags,[string]$Options) {
    if ($CaptureMode -eq "baseline") {
        if ($Flags -or $Options) { throw "Baseline cannot enable candidate flags or options" }
        return
    }
    if (!$Flags) { throw "Candidate requires explicit -Features a,d,e subset" }
    $items = @($Flags.Split(','))
    if (@($items | Where-Object { $_ -cnotin @("a","d","e") }).Count -gt 0 -or
        @($items | Select-Object -Unique).Count -ne $items.Count) {
        throw "Unknown, empty or duplicate candidate flag"
    }
}

function Invoke-BoundedNative([string]$Executable,[string[]]$Arguments,[string]$Stdout,[string]$Stderr,[int]$TimeoutSeconds,[switch]$AnnounceCapture) {
    $joined = Join-NativeArguments $Arguments
    $process = Start-Process -FilePath $Executable -ArgumentList $joined -PassThru -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
    # Windows PowerShell 5.1 can lose ExitCode after WaitForExit unless the
    # Process object acquires and retains its native handle before exit.
    $null = $process.Handle
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $announced = $false
    try {
        while (!$process.WaitForExit(500)) {
            if ($AnnounceCapture -and !$announced -and (Test-Path -LiteralPath $Stdout) -and
                (Select-String -Quiet -LiteralPath $Stdout -Pattern 'CAPTURE START')) {
                Write-Host "CAPTURE START - manual scenario: drive now"
                $announced = $true
            }
            if ($timer.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                $process.Kill()
                $process.WaitForExit()
                throw "Native process timeout; inspect $Stdout and $Stderr"
            }
        }
        $process.WaitForExit()
        $code=$process.ExitCode
        if ($null -eq $code) { throw "Native process exit code unavailable; inspect $Stdout and $Stderr" }
        return [int]$code
    } finally {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

if ($SelfTest) {
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ("aster qa contract " + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    try {
        Assert-FeatureSelection "baseline" "" ""
        Assert-FeatureSelection "candidate" "a,d,e" ""
        foreach ($bad in @("a,a","A","a,","", "a, d", 'a"e')) {
            $rejected = $false
            try { Assert-FeatureSelection "candidate" $bad "" } catch { $rejected = $true }
            if (!$rejected) { throw "Feature fixture accepted invalid flags: $bad" }
        }
        $python = (Get-Command python -ErrorAction Stop).Source
        $echoScript = Join-Path $scratch "echo args.py"
        [IO.File]::WriteAllText($echoScript,'import json,sys; expected=json.load(open(sys.argv[1],encoding="utf-8")); actual=sys.argv[2:]; print(json.dumps(actual)); sys.exit(0 if actual==expected else 9)')
        $expected = @("", "two words", "C:\folder with space\", "--features=", "a,d,e", "--out=$scratch")
        $expectedPath = Join-Path $scratch "expected args.json"
        [IO.File]::WriteAllText($expectedPath,(ConvertTo-Json -InputObject $expected -Compress),[Text.UTF8Encoding]::new($false))
        $stdout = Join-Path $scratch "stdout.log"
        $stderr = Join-Path $scratch "stderr.log"
        $status = Invoke-BoundedNative $python (@($echoScript,$expectedPath)+$expected) $stdout $stderr 15
        if ($status -ne 0) { throw "Native argv fixture failed: $status; $(Get-Content -LiteralPath $stderr -Raw)" }
        Write-Host "Native argv verified: $(Get-Content -LiteralPath $stdout -Raw)"
        $sleepScript=Join-Path $scratch "sleep.py"
        [IO.File]::WriteAllText($sleepScript,'import time; time.sleep(30)')
        $timedOut=$false
        try { $null=Invoke-BoundedNative $python @($sleepScript) $stdout $stderr 1 } catch {
            $timedOut=$_.Exception.Message -like "Native process timeout*"
        }
        if (!$timedOut) { throw "Timeout fixture failed" }
        Write-Host "PASS Windows native quoting, feature validation and bounded process contract"
    } catch {
        foreach ($log in @("stdout.log","stderr.log")) {
            $logPath=Join-Path $scratch $log
            if (Test-Path -LiteralPath $logPath) { Write-Host (Get-Content -LiteralPath $logPath -Raw) }
        }
        throw
    } finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
    return
}

Assert-FeatureSelection $Mode $Features $OptionsFile
$Root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$Godot=(Resolve-Path -LiteralPath $Godot).Path
if (!(Test-Path -LiteralPath $Godot -PathType Leaf)) { throw "Godot console executable required" }
if ($OptionsFile) { $OptionsFile=(Resolve-Path -LiteralPath $OptionsFile).Path }
$Output=[IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) { throw "Use a new output directory: $Output" }
if ($Output.Equals($Root,[StringComparison]::OrdinalIgnoreCase) -or
    $Output.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Capture outside the repository"
}
if ([double]::IsNaN($SpeedMps) -or [double]::IsInfinity($SpeedMps)) { throw "Invalid speed" }

Push-Location $Root
$ownedOutput=$false
try {
    $commit=(git rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or "$commit" -notmatch '^[0-9a-f]{40}$') { throw "Git revision unavailable" }
    $dirty=git status --porcelain --untracked-files=all
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw "Tracked or untracked changes present; commit first for reproducibility" }
    New-Item -ItemType Directory -Path $Output | Out-Null
    $ownedOutput=$true
    $versionOut=Join-Path $Output "version.log"
    $versionErr=Join-Path $Output "version-stderr.log"
    $versionStatus=Invoke-BoundedNative $Godot @("--headless","--version") $versionOut $versionErr 20
    $version=Get-Content -LiteralPath $versionOut -Raw
    if ($versionStatus -ne 0 -or "$version" -notmatch '^4\.7\.2\.stable') { throw "Use pinned Godot 4.7.2 stable" }
    $speed=$SpeedMps.ToString([Globalization.CultureInfo]::InvariantCulture)
    $engineArgs=@("--path",$Root,"--rendering-method","forward_plus","--resolution","1920x1080",
        "--script","res://tests/environment_overhaul/capture.gd","--",
        "--out=$Output","--mode=$Mode","--site=$Site","--scenario=$Scenario","--preset=$Preset",
        "--features=$Features","--seconds=$Seconds","--warmup=$Warmup","--speed-mps=$speed","--commit=$commit")
    if ($OptionsFile) { $engineArgs+="--options=$OptionsFile" }
    if ($Interaction) { $engineArgs+="--interaction=on" }
    $stdout=Join-Path $Output "stdout.log"
    $stderr=Join-Path $Output "stderr.log"
    $console=Join-Path $Output "console.log"
    try {
        $status=Invoke-BoundedNative $Godot $engineArgs $stdout $stderr ($Seconds+$Warmup+180) -AnnounceCapture
    } finally {
        @((Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue),(Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue)) |
            Set-Content -LiteralPath $console
    }
    if ($status -ne 0 -or (Select-String -Quiet -LiteralPath $console -Pattern 'SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|Shader error|^FAIL(?:ED)?(?:\s|:)')) {
        throw "Capture failed; inspect console.log"
    }
    foreach ($name in @("meta.json","frames.csv","start.png","end.png")) {
        if (!(Test-Path -LiteralPath (Join-Path $Output $name) -PathType Leaf)) { throw "Capture incomplete: $name" }
    }
    $metaPath=Join-Path $Output "meta.json"
    $metadata=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    if ($metadata.complete -ne $true) { throw "Incomplete capture metadata" }
    foreach ($name in @("frames.csv","start.png","end.png")) {
        $actualHash=(Get-FileHash -LiteralPath (Join-Path $Output $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($metadata.sha256_by_file.$name -ne $actualHash) { throw "Artifact hash mismatch: $name" }
    }
    try {
        $adapters=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)
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
} finally {
    if ($ownedOutput) {
        # Only the private, uniquely created capture directory is touched.
        Get-ChildItem -LiteralPath $Output -File -Filter "qa-profile-*.json*" |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
