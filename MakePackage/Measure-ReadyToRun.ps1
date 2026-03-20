Param(
    [ValidateSet("Release")][string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [Alias("Runs")][int]$RunCount = 3,
    [switch]$SelfContained,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$solutionDir = Convert-Path "$scriptPath\.."
$project = Join-Path $solutionDir "NeeView\NeeView.csproj"
$projectSusie = Join-Path $solutionDir "NeeView.Susie.Server\NeeView.Susie.Server.csproj"
$dotnet = Join-Path $env:USERPROFILE ".dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) {
    $dotnet = "dotnet"
}
$requiredProjectPaths = @(
    (Join-Path $solutionDir "AnimatedImage\AnimatedImage.Wpf\AnimatedImage.Wpf.csproj"),
    (Join-Path $solutionDir "NeeLaboratory.IO.Search\NeeLaboratory.IO.Search\NeeLaboratory.IO.Search.csproj"),
    (Join-Path $solutionDir "SevenZipSharp\SevenZip\SevenZip.csproj"),
    (Join-Path $solutionDir "Vlc.DotNet\src\Vlc.DotNet.Wpf\Vlc.DotNet.Wpf.csproj")
)

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $solutionDir "artifacts\readytorun-experiment"
}

$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

function New-CleanDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path | Out-Null
}

function Assert-Prerequisites {
    [xml]$projectXml = Get-Content $project
    $targetFramework = $projectXml.Project.PropertyGroup.TargetFramework | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($targetFramework)) {
        throw "Cannot determine TargetFramework from $project"
    }

    if ($targetFramework -notmatch '^net(\d+)\.') {
        throw "Unsupported TargetFramework format: $targetFramework"
    }

    $requiredSdkMajor = [int]$Matches[1]
    $installedSdks = & $dotnet --list-sdks
    $hasRequiredSdk = $installedSdks | Where-Object { $_ -match "^$requiredSdkMajor\." }
    if (-not $hasRequiredSdk) {
        throw "This experiment requires .NET SDK $requiredSdkMajor.x for target framework '$targetFramework'. Current SDKs: $($installedSdks -join ', ')"
    }

    $missingProjects = $requiredProjectPaths | Where-Object { -not (Test-Path $_) }
    if ($missingProjects.Count -gt 0) {
        $missingList = $missingProjects -join "; "
        throw "Required submodule projects are missing: $missingList. Run 'git submodule update --init --recursive' first."
    }
}

function Get-DirectorySizeBytes {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return [int64]0
    }

    $sum = (Get-ChildItem $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) {
        return [int64]0
    }

    return [int64]$sum
}

function Publish-Variant {
    param(
        [string]$Name,
        [bool]$PublishReadyToRun
    )

    $publishDir = Join-Path $OutputRoot $Name
    New-CleanDirectory $publishDir

    $selfContainedValue = if ($SelfContained) { "true" } else { "false" }
    $r2rValue = if ($PublishReadyToRun) { "true" } else { "false" }

    $publishArgs = @(
        "publish", $project,
        "-c", $Configuration,
        "-r", $RuntimeIdentifier,
        "-o", $publishDir,
        "-p:Platform=x64",
        "-p:PublishSingleFile=false",
        "-p:PublishTrimmed=false",
        "-p:SelfContained=$selfContainedValue",
        "-p:PublishReadyToRun=$r2rValue"
    )

    Write-Host "> $dotnet $($publishArgs -join ' ')" -ForegroundColor Cyan
    & $dotnet @publishArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Publish failed: $Name"
    }

    $susieDir = Join-Path $publishDir "Libraries\Susie"
    New-Item -ItemType Directory -Path $susieDir -Force | Out-Null

    $susieArgs = @(
        "publish", $projectSusie,
        "-c", $Configuration,
        "-r", "win-x86",
        "-o", $susieDir,
        "-p:Platform=x86",
        "-p:PlatformTarget=x86"
    )

    Write-Host "> $dotnet $($susieArgs -join ' ')" -ForegroundColor Cyan
    & $dotnet @susieArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Publish failed (Susie): $Name"
    }

    return [pscustomobject]@{
        Name = $Name
        PublishReadyToRun = $PublishReadyToRun
        PublishDir = $publishDir
        ExePath = Join-Path $publishDir "NeeView.exe"
        SizeBytes = Get-DirectorySizeBytes $publishDir
    }
}

function Start-NeeViewMeasurement {
    param(
        [string]$ExePath,
        [string]$ProfileDir
    )

    New-CleanDirectory $ProfileDir

    $psi = [System.Diagnostics.ProcessStartInfo]::new($ExePath)
    $psi.WorkingDirectory = Split-Path -Parent $ExePath
    $psi.UseShellExecute = $false
    $psi.ArgumentList.Add("--blank")
    $psi.ArgumentList.Add("--new-window=on")
    $psi.ArgumentList.Add("--reset-placement")
    $psi.Environment["NEEVIEW_PROFILE"] = $ProfileDir
    if ($dotnet -ne "dotnet") {
        $dotnetRoot = Split-Path -Parent $dotnet
        $psi.Environment["DOTNET_ROOT"] = $dotnetRoot
        $psi.Environment["DOTNET_ROOT_X64"] = $dotnetRoot
        $psi.Environment["PATH"] = "$dotnetRoot;$($psi.Environment["PATH"])"
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) {
        throw "Failed to start process: $ExePath"
    }

    try {
        $timeoutAt = [DateTime]::UtcNow.AddSeconds(60)
        while ($process.MainWindowHandle -eq 0 -and -not $process.HasExited) {
            if ([DateTime]::UtcNow -gt $timeoutAt) {
                throw "Timed out waiting for main window."
            }

            Start-Sleep -Milliseconds 50
            $process.Refresh()
        }

        if ($process.HasExited) {
            throw "Process exited before showing main window. ExitCode=$($process.ExitCode)"
        }

        $stopwatch.Stop()

        Start-Sleep -Milliseconds 1000
        $process.Refresh()

        return [pscustomobject]@{
            StartupMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
            WorkingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
            PrivateMemoryMB = [math]::Round($process.PrivateMemorySize64 / 1MB, 1)
        }
    }
    finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }

        $process.Dispose()
    }
}

function Measure-Variant {
    param([pscustomobject]$Variant)

    $runs = @()
    for ($i = 1; $i -le $script:RunCount; $i++) {
        Write-Host "[$($Variant.Name)] Run $i/$($script:RunCount)" -ForegroundColor Yellow
        $profileDir = Join-Path $OutputRoot "profiles\$($Variant.Name)\run-$i"
        $runs += Start-NeeViewMeasurement -ExePath $Variant.ExePath -ProfileDir $profileDir
    }

    $startupAverage = ($runs | Measure-Object -Property StartupMs -Average).Average
    $workingSetAverage = ($runs | Measure-Object -Property WorkingSetMB -Average).Average
    $privateAverage = ($runs | Measure-Object -Property PrivateMemoryMB -Average).Average

    return [pscustomobject]@{
        Name = $Variant.Name
        PublishReadyToRun = $Variant.PublishReadyToRun
        SizeBytes = $Variant.SizeBytes
        SizeMB = [math]::Round($Variant.SizeBytes / 1MB, 1)
        StartupMsAverage = [math]::Round($startupAverage, 1)
        WorkingSetMBAverage = [math]::Round($workingSetAverage, 1)
        PrivateMemoryMBAverage = [math]::Round($privateAverage, 1)
        Runs = $runs
    }
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Assert-Prerequisites

$variants = @(
    (Publish-Variant -Name "baseline-no-r2r" -PublishReadyToRun $false),
    (Publish-Variant -Name "experiment-r2r" -PublishReadyToRun $true)
)

$results = $variants | ForEach-Object { Measure-Variant $_ }

$table = $results | Select-Object `
    Name,
    PublishReadyToRun,
    SizeMB,
    StartupMsAverage,
    WorkingSetMBAverage,
    PrivateMemoryMBAverage

$table | Format-Table -AutoSize

$jsonPath = Join-Path $OutputRoot "results.json"
$table | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $jsonPath

Write-Host ""
Write-Host "Results saved to $jsonPath" -ForegroundColor Green
