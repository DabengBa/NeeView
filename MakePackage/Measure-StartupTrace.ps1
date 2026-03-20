Param(
    [ValidateSet("Release")][string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [Alias("Runs")][int]$RunCount = 5,
    [string]$BaselineRef = "HEAD",
    [string]$OutputRoot = "",
    [string]$SeedProfilePath = "",
    [int]$TraceTimeoutSeconds = 90,
    [int]$TraceRetryCount = 1,
    [switch]$SkipPublish
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
    $OutputRoot = Join-Path $solutionDir "artifacts\startup-trace-compare"
}

if ([string]::IsNullOrWhiteSpace($SeedProfilePath)) {
    $candidateSeed = Join-Path $solutionDir "NeeView\bin\x64\Release\net10.0-windows\win-x64\Profile"
    if (Test-Path $candidateSeed) {
        $SeedProfilePath = $candidateSeed
    }
}

$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

function New-CleanDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if (-not (Test-Path $Source)) {
        return
    }

    Get-ChildItem -Force $Source | ForEach-Object {
        Copy-Item $_.FullName -Destination $Destination -Recurse -Force
    }
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

function Copy-WorkspaceSnapshot {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-CleanDirectory $Destination

    $excludeDirs = @(
        (Join-Path $Source ".git"),
        (Join-Path $Source "artifacts")
    )

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/E",
        "/R:1",
        "/W:1",
        "/NFL",
        "/NDL",
        "/NJH",
        "/NJS",
        "/NP",
        "/XD"
    ) + $excludeDirs

    & robocopy @robocopyArgs | Out-Host
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed while creating baseline workspace. ExitCode=$LASTEXITCODE"
    }

    Get-ChildItem -Path $Destination -Directory -Recurse -Force |
        Where-Object { $_.Name -in @("bin", "obj") } |
        Sort-Object FullName -Descending |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

function Write-GitTextFile {
    param(
        [string]$Ref,
        [string]$RepoRelativePath,
        [string]$DestinationPath
    )

    $content = & git -C $solutionDir show "$Ref`:$RepoRelativePath"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read '$RepoRelativePath' from git ref '$Ref'."
    }

    $normalized = if ($content -is [System.Array]) { ($content -join [Environment]::NewLine) } else { [string]$content }
    Set-Content -Path $DestinationPath -Value $normalized -Encoding UTF8
}

function Remove-WorkspacePathIfExists {
    param(
        [string]$WorkspaceDir,
        [string]$RepoRelativePath
    )

    $fullPath = Join-Path $WorkspaceDir $RepoRelativePath
    if (Test-Path $fullPath) {
        Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Restore-WorkspaceToGitRef {
    param(
        [string]$Ref,
        [string]$WorkspaceDir
    )

    $diffLines = & git -C $solutionDir diff --name-status --find-renames $Ref --
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to diff working tree against git ref '$Ref'."
    }

    foreach ($line in $diffLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t"
        $status = $parts[0]

        if ($status.StartsWith("R")) {
            $oldPath = $parts[1]
            $newPath = $parts[2]
            Remove-WorkspacePathIfExists -WorkspaceDir $WorkspaceDir -RepoRelativePath $newPath
            $destinationPath = Join-Path $WorkspaceDir $oldPath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
            Write-GitTextFile -Ref $Ref -RepoRelativePath $oldPath -DestinationPath $destinationPath
            continue
        }

        $path = $parts[1]
        switch -Regex ($status) {
            '^A' {
                Remove-WorkspacePathIfExists -WorkspaceDir $WorkspaceDir -RepoRelativePath $path
                continue
            }
            '^D' {
                $destinationPath = Join-Path $WorkspaceDir $path
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
                Write-GitTextFile -Ref $Ref -RepoRelativePath $path -DestinationPath $destinationPath
                continue
            }
            default {
                $destinationPath = Join-Path $WorkspaceDir $path
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
                Write-GitTextFile -Ref $Ref -RepoRelativePath $path -DestinationPath $destinationPath
                continue
            }
        }
    }

    $untrackedLines = & git -C $solutionDir ls-files --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enumerate untracked files in working tree."
    }

    foreach ($path in $untrackedLines) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        Remove-WorkspacePathIfExists -WorkspaceDir $WorkspaceDir -RepoRelativePath $path
    }
}

function New-TraceBaselineWorkspace {
    param(
        [string]$Ref,
        [string]$WorktreePath
    )

    if (Test-Path $WorktreePath) {
        Remove-Item $WorktreePath -Recurse -Force
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $WorktreePath) -Force | Out-Null
    Write-Host "> Create baseline workspace at $WorktreePath" -ForegroundColor Cyan
    Copy-WorkspaceSnapshot -Source $solutionDir -Destination $WorktreePath
    Restore-WorkspaceToGitRef -Ref $Ref -WorkspaceDir $WorktreePath
}

function Publish-Variant {
    param(
        [string]$Name,
        [string]$WorkspaceDir,
        [bool]$PublishReadyToRun
    )

    $publishDir = Join-Path $OutputRoot $Name
    New-CleanDirectory $publishDir

    $workspaceProject = Join-Path $WorkspaceDir "NeeView\NeeView.csproj"
    $workspaceProjectSusie = Join-Path $WorkspaceDir "NeeView.Susie.Server\NeeView.Susie.Server.csproj"

    $r2rValue = if ($PublishReadyToRun) { "true" } else { "false" }

    $publishArgs = @(
        "publish", $workspaceProject,
        "-c", $Configuration,
        "-r", $RuntimeIdentifier,
        "-o", $publishDir,
        "-p:Platform=x64",
        "-p:PublishSingleFile=false",
        "-p:PublishTrimmed=false",
        "-p:SelfContained=false",
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
        "publish", $workspaceProjectSusie,
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

function Set-VariantTraceLog {
    param(
        [string]$PublishDir,
        [string]$RelativeLogFile
    )

    $settingsPath = Join-Path $PublishDir "NeeView.settings.json"
    $json = Get-Content -Raw $settingsPath | ConvertFrom-Json
    $json.LogFile = $RelativeLogFile
    $json | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 $settingsPath
}

function Parse-StartupTraceLog {
    param([string]$LogPath)

    if (-not (Test-Path $LogPath)) {
        return $null
    }

    $labels = @{}
    foreach ($line in Get-Content $LogPath) {
        if ($line -notmatch 'Startup\.Trace\|(?<label>[^|]+)\|(?<payload>.+)$') {
            continue
        }

        $label = $Matches.label
        if (-not $labels.ContainsKey($label)) {
            $labels[$label] = @{}
        }

        foreach ($part in ($Matches.payload -split '\|')) {
            if ($part -notmatch '^(?<key>[A-Za-z_]+)=(?<value>-?\d+)$') {
                continue
            }

            $labels[$label][$Matches.key] = [int64]$Matches.value
        }
    }

    return $labels
}

function Wait-TraceMetrics {
    param(
        [string]$LogPath,
        [hashtable]$RequiredLabelKeys,
        [int]$TimeoutSeconds = 60
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $parsed = Parse-StartupTraceLog -LogPath $LogPath
        if ($null -ne $parsed) {
            $ready = $true
            foreach ($label in $RequiredLabelKeys.Keys) {
                if (-not $parsed.ContainsKey($label)) {
                    $ready = $false
                    break
                }

                $entry = $parsed[$label]
                $requiredKey = $RequiredLabelKeys[$label]
                if (-not $entry.ContainsKey($requiredKey)) {
                    $ready = $false
                    break
                }
            }

            if ($ready) {
                return $parsed
            }
        }

        Start-Sleep -Milliseconds 100
    }

    throw "Timed out waiting for startup trace metrics in '$LogPath'."
}

function Get-TraceMetricValue {
    param(
        [hashtable]$TraceEntries,
        [string]$Label,
        [string]$Key
    )

    if ($null -eq $TraceEntries) {
        return $null
    }

    if (-not $TraceEntries.ContainsKey($Label)) {
        return $null
    }

    $entry = $TraceEntries[$Label]
    if (-not $entry.ContainsKey($Key)) {
        return $null
    }

    return [double]$entry[$Key]
}

function Get-TraceMetricDelta {
    param(
        [hashtable]$TraceEntries,
        [string]$StartLabel,
        [string]$StartKey,
        [string]$EndLabel,
        [string]$EndKey
    )

    $start = Get-TraceMetricValue -TraceEntries $TraceEntries -Label $StartLabel -Key $StartKey
    $end = Get-TraceMetricValue -TraceEntries $TraceEntries -Label $EndLabel -Key $EndKey
    if ($null -eq $start -or $null -eq $end) {
        return $null
    }

    return [double]($end - $start)
}

function Convert-ToRoundedNullable {
    param(
        $Value,
        [int]$Digits = 1
    )

    if ($null -eq $Value) {
        return $null
    }

    return [math]::Round([double]$Value, $Digits)
}

function Stop-ProcessGracefully {
    param([System.Diagnostics.Process]$Process)

    if ($Process.HasExited) {
        return
    }

    $null = $Process.CloseMainWindow()
    if (-not $Process.WaitForExit(15000)) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        $Process.WaitForExit(5000) | Out-Null
    }
}

function Start-TraceRun {
    param(
        [pscustomobject]$Variant,
        [string]$ProfileDir,
        [string]$RelativeLogFile = "startup-trace.log"
    )

    $requiredLabels = @{
        "MainWindow.Loaded" = "end_ms"
        "MainWindow.ContentRendered" = "start_ms"
        "MainWindow.ContentRendered.ViewModel" = "end_ms"
        "MainWindowModel.LoadedAsync" = "duration_ms"
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new($Variant.ExePath)
    $psi.WorkingDirectory = $Variant.PublishDir
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

    $logPath = Join-Path $ProfileDir $RelativeLogFile
    if (Test-Path $logPath) {
        Remove-Item $logPath -Force
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) {
        throw "Failed to start process: $($Variant.ExePath)"
    }

    $trace = $null
    $workingSetMB = $null
    $privateMemoryMB = $null

    try {
        $trace = Wait-TraceMetrics -LogPath $logPath -RequiredLabelKeys $requiredLabels -TimeoutSeconds $TraceTimeoutSeconds
        Start-Sleep -Milliseconds 300
        $process.Refresh()
        $workingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
        $privateMemoryMB = [math]::Round($process.PrivateMemorySize64 / 1MB, 1)
    }
    finally {
        Stop-ProcessGracefully -Process $process
        $process.Dispose()
    }

    $finalTrace = Parse-StartupTraceLog -LogPath $logPath
    if ($null -ne $finalTrace) {
        $trace = $finalTrace
    }

    if ($null -eq $trace) {
        throw "Startup trace parse returned null for '$logPath'."
    }

    $result = [ordered]@{
        T3LoadedEndMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.Loaded" -Key "end_ms"), 1)
        T4ContentRenderedStartMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.ContentRendered" -Key "start_ms"), 1)
        T5ViewModelEndMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.ContentRendered.ViewModel" -Key "end_ms"), 1)
        ContentRenderedEndMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.ContentRendered" -Key "end_ms"), 1)
        LoadedAsyncDurationMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindowModel.LoadedAsync" -Key "duration_ms"), 1)
        LoadedAsyncTailMs = [math]::Round((Get-TraceMetricDelta -TraceEntries $trace -StartLabel "MainWindowModel.LoadedAsync" -StartKey "end_ms" -EndLabel "MainWindow.ContentRendered.ViewModel" -EndKey "end_ms"), 1)
        LoadedAsyncResumeGapMs = $(Convert-ToRoundedNullable -Value (Get-TraceMetricDelta -TraceEntries $trace -StartLabel "MainWindowModel.LoadedAsync" -StartKey "end_ms" -EndLabel "MainWindowViewModel.InitializeAsync.Model.LoadedAsync.Returned" -EndKey "mark_ms"))
        StartupRequestBookmarkMs = $(Convert-ToRoundedNullable -Value (Get-TraceMetricValue -TraceEntries $trace -Label "FolderList.StartupRequestPlace.BookmarkFolderList" -Key "duration_ms"))
        StartupRequestBookshelfMs = $(Convert-ToRoundedNullable -Value (Get-TraceMetricValue -TraceEntries $trace -Label "FolderList.StartupRequestPlace.BookshelfFolderList" -Key "duration_ms"))
        StartupRequestBookmarkQueueMs = $(Convert-ToRoundedNullable -Value (Get-TraceMetricDelta -TraceEntries $trace -StartLabel "FolderList.StartupRequestPlace.BookmarkFolderList.Queued" -StartKey "mark_ms" -EndLabel "FolderList.StartupRequestPlace.BookmarkFolderList" -EndKey "start_ms"))
        StartupRequestBookshelfQueueMs = $(Convert-ToRoundedNullable -Value (Get-TraceMetricDelta -TraceEntries $trace -StartLabel "FolderList.StartupRequestPlace.BookshelfFolderList.Queued" -StartKey "mark_ms" -EndLabel "FolderList.StartupRequestPlace.BookshelfFolderList" -EndKey "start_ms"))
        WorkingSetMB = $workingSetMB
        PrivateMemoryMB = $privateMemoryMB
        Trace = $trace
        LogPath = $logPath
    }

    return [pscustomobject]$result
}

function Invoke-TraceRunWithRetry {
    param(
        [pscustomobject]$Variant,
        [string]$SeedProfileDir,
        [string]$ProfileDir,
        [string]$DisplayName
    )

    $maxAttempts = [Math]::Max(1, $TraceRetryCount + 1)
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        New-CleanDirectory $ProfileDir
        Copy-DirectoryContents -Source $SeedProfileDir -Destination $ProfileDir

        $attemptSuffix = if ($maxAttempts -gt 1) { " (attempt $attempt/$maxAttempts)" } else { "" }
        Write-Host "$DisplayName$attemptSuffix" -ForegroundColor Yellow

        try {
            return Start-TraceRun -Variant $Variant -ProfileDir $ProfileDir
        }
        catch {
            if ($attempt -ge $maxAttempts) {
                throw
            }

            Write-Warning "$DisplayName failed: $($_.Exception.Message). Retrying..."
        }
    }
}

function Measure-Variant {
    param(
        [pscustomobject]$Variant,
        [string]$BaseProfileTemplate
    )

    $variantRoot = Join-Path $OutputRoot "profiles\$($Variant.Name)"
    $warmupProfile = Join-Path $variantRoot "warmup"
    $warmedTemplate = Join-Path $variantRoot "warmed-template"

    New-CleanDirectory $variantRoot

    $null = Invoke-TraceRunWithRetry -Variant $Variant -SeedProfileDir $BaseProfileTemplate -ProfileDir $warmupProfile -DisplayName "[$($Variant.Name)] Warmup"

    New-CleanDirectory $warmedTemplate
    Copy-DirectoryContents -Source $warmupProfile -Destination $warmedTemplate

    $runs = @()
    for ($i = 1; $i -le $script:RunCount; $i++) {
        $runProfile = Join-Path $variantRoot "run-$i"
        $runs += Invoke-TraceRunWithRetry -Variant $Variant -SeedProfileDir $warmedTemplate -ProfileDir $runProfile -DisplayName "[$($Variant.Name)] Run $i/$($script:RunCount)"
    }

    $t3Average = ($runs | Measure-Object -Property T3LoadedEndMs -Average).Average
    $t4Average = ($runs | Measure-Object -Property T4ContentRenderedStartMs -Average).Average
    $t5Average = ($runs | Measure-Object -Property T5ViewModelEndMs -Average).Average
    $contentRenderedAverage = ($runs | Measure-Object -Property ContentRenderedEndMs -Average).Average
    $loadedAsyncAverage = ($runs | Measure-Object -Property LoadedAsyncDurationMs -Average).Average
    $loadedAsyncTailAverage = ($runs | ForEach-Object {
        if ($null -ne $_.LoadedAsyncTailMs) { $_.LoadedAsyncTailMs }
    } | Measure-Object -Average).Average
    $loadedAsyncResumeGapAverage = ($runs | ForEach-Object {
        if ($null -ne $_.LoadedAsyncResumeGapMs) { $_.LoadedAsyncResumeGapMs }
    } | Measure-Object -Average).Average
    $workingSetAverage = ($runs | Measure-Object -Property WorkingSetMB -Average).Average
    $privateAverage = ($runs | Measure-Object -Property PrivateMemoryMB -Average).Average
    $startupRequestBookmarkAverage = ($runs | ForEach-Object {
        if ($null -ne $_.StartupRequestBookmarkMs) { $_.StartupRequestBookmarkMs }
    } | Measure-Object -Average).Average
    $startupRequestBookshelfAverage = ($runs | ForEach-Object {
        if ($null -ne $_.StartupRequestBookshelfMs) { $_.StartupRequestBookshelfMs }
    } | Measure-Object -Average).Average
    $startupRequestBookmarkQueueAverage = ($runs | ForEach-Object {
        if ($null -ne $_.StartupRequestBookmarkQueueMs) { $_.StartupRequestBookmarkQueueMs }
    } | Measure-Object -Average).Average
    $startupRequestBookshelfQueueAverage = ($runs | ForEach-Object {
        if ($null -ne $_.StartupRequestBookshelfQueueMs) { $_.StartupRequestBookshelfQueueMs }
    } | Measure-Object -Average).Average

    $susieAverage = ($runs | ForEach-Object {
        $value = Get-TraceMetricValue -TraceEntries $_.Trace -Label "MainWindowModel.LoadedAsync.SusiePluginManager.Initialize" -Key "duration_ms"
        if ($null -ne $value) { $value }
    } | Measure-Object -Average).Average

    $bookmarkWaitAverage = ($runs | ForEach-Object {
        $value = Get-TraceMetricValue -TraceEntries $_.Trace -Label "MainWindowModel.LoadedAsync.BookmarkFolderList.WaitAsync" -Key "duration_ms"
        if ($null -ne $value) { $value }
    } | Measure-Object -Average).Average

    $bookshelfWaitAverage = ($runs | ForEach-Object {
        $value = Get-TraceMetricValue -TraceEntries $_.Trace -Label "MainWindowModel.LoadedAsync.BookshelfFolderList.WaitAsync" -Key "duration_ms"
        if ($null -ne $value) { $value }
    } | Measure-Object -Average).Average

    $warmupBookmarkAverage = ($runs | ForEach-Object {
        $value = Get-TraceMetricValue -TraceEntries $_.Trace -Label "MainWindowModel.StartupWarmup.BookmarkFolderList.WaitAsync" -Key "duration_ms"
        if ($null -ne $value) { $value }
    } | Measure-Object -Average).Average

    $warmupBookshelfAverage = ($runs | ForEach-Object {
        $value = Get-TraceMetricValue -TraceEntries $_.Trace -Label "MainWindowModel.StartupWarmup.BookshelfFolderList.WaitAsync" -Key "duration_ms"
        if ($null -ne $value) { $value }
    } | Measure-Object -Average).Average

    return [pscustomobject]@{
        Name = $Variant.Name
        PublishReadyToRun = $Variant.PublishReadyToRun
        SizeBytes = $Variant.SizeBytes
        SizeMB = [math]::Round($Variant.SizeBytes / 1MB, 1)
        T3LoadedEndMsAverage = [math]::Round($t3Average, 1)
        T4ContentRenderedStartMsAverage = [math]::Round($t4Average, 1)
        T5ViewModelEndMsAverage = [math]::Round($t5Average, 1)
        ContentRenderedEndMsAverage = [math]::Round($contentRenderedAverage, 1)
        LoadedAsyncDurationMsAverage = [math]::Round($loadedAsyncAverage, 1)
        LoadedAsyncTailMsAverage = if ($null -eq $loadedAsyncTailAverage) { $null } else { [math]::Round($loadedAsyncTailAverage, 1) }
        LoadedAsyncResumeGapMsAverage = if ($null -eq $loadedAsyncResumeGapAverage) { $null } else { [math]::Round($loadedAsyncResumeGapAverage, 1) }
        WorkingSetMBAverage = [math]::Round($workingSetAverage, 1)
        PrivateMemoryMBAverage = [math]::Round($privateAverage, 1)
        SusieInitializeDurationMsAverage = if ($null -eq $susieAverage) { $null } else { [math]::Round($susieAverage, 1) }
        LoadedBookmarkWaitMsAverage = if ($null -eq $bookmarkWaitAverage) { $null } else { [math]::Round($bookmarkWaitAverage, 1) }
        LoadedBookshelfWaitMsAverage = if ($null -eq $bookshelfWaitAverage) { $null } else { [math]::Round($bookshelfWaitAverage, 1) }
        WarmupBookmarkWaitMsAverage = if ($null -eq $warmupBookmarkAverage) { $null } else { [math]::Round($warmupBookmarkAverage, 1) }
        WarmupBookshelfWaitMsAverage = if ($null -eq $warmupBookshelfAverage) { $null } else { [math]::Round($warmupBookshelfAverage, 1) }
        StartupRequestBookmarkMsAverage = if ($null -eq $startupRequestBookmarkAverage) { $null } else { [math]::Round($startupRequestBookmarkAverage, 1) }
        StartupRequestBookshelfMsAverage = if ($null -eq $startupRequestBookshelfAverage) { $null } else { [math]::Round($startupRequestBookshelfAverage, 1) }
        StartupRequestBookmarkQueueMsAverage = if ($null -eq $startupRequestBookmarkQueueAverage) { $null } else { [math]::Round($startupRequestBookmarkQueueAverage, 1) }
        StartupRequestBookshelfQueueMsAverage = if ($null -eq $startupRequestBookshelfQueueAverage) { $null } else { [math]::Round($startupRequestBookshelfQueueAverage, 1) }
        Runs = $runs
    }
}

Assert-Prerequisites
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$profileTemplate = Join-Path $OutputRoot "profile-template"
New-CleanDirectory $profileTemplate
if (-not [string]::IsNullOrWhiteSpace($SeedProfilePath) -and (Test-Path $SeedProfilePath)) {
    Write-Host "Using seed profile: $SeedProfilePath" -ForegroundColor DarkCyan
    Copy-DirectoryContents -Source $SeedProfilePath -Destination $profileTemplate
}
else {
    Write-Host "Seed profile not found. Falling back to empty profile template." -ForegroundColor DarkYellow
}

$baselineWorktree = Join-Path $OutputRoot "worktrees\trace-baseline"

try {
    New-TraceBaselineWorkspace -Ref $BaselineRef -WorktreePath $baselineWorktree

    $variants = @()
    if (-not $SkipPublish) {
        $variants += Publish-Variant -Name "trace-baseline" -WorkspaceDir $baselineWorktree -PublishReadyToRun $true
        $variants += Publish-Variant -Name "current-optimized" -WorkspaceDir $solutionDir -PublishReadyToRun $true
    }
    else {
        $variants += [pscustomobject]@{
            Name = "trace-baseline"
            PublishReadyToRun = $true
            PublishDir = Join-Path $OutputRoot "trace-baseline"
            ExePath = Join-Path $OutputRoot "trace-baseline\NeeView.exe"
            SizeBytes = Get-DirectorySizeBytes (Join-Path $OutputRoot "trace-baseline")
        }
        $variants += [pscustomobject]@{
            Name = "current-optimized"
            PublishReadyToRun = $true
            PublishDir = Join-Path $OutputRoot "current-optimized"
            ExePath = Join-Path $OutputRoot "current-optimized\NeeView.exe"
            SizeBytes = Get-DirectorySizeBytes (Join-Path $OutputRoot "current-optimized")
        }
    }

    foreach ($variant in $variants) {
        Set-VariantTraceLog -PublishDir $variant.PublishDir -RelativeLogFile "startup-trace.log"
    }

    $results = $variants | ForEach-Object { Measure-Variant -Variant $_ -BaseProfileTemplate $profileTemplate }

    $summary = $results | Select-Object `
        Name,
        SizeMB,
        T3LoadedEndMsAverage,
        T4ContentRenderedStartMsAverage,
        T5ViewModelEndMsAverage,
        ContentRenderedEndMsAverage,
        LoadedAsyncDurationMsAverage,
        LoadedAsyncTailMsAverage,
        LoadedAsyncResumeGapMsAverage,
        WorkingSetMBAverage,
        PrivateMemoryMBAverage,
        SusieInitializeDurationMsAverage,
        LoadedBookmarkWaitMsAverage,
        LoadedBookshelfWaitMsAverage,
        WarmupBookmarkWaitMsAverage,
        WarmupBookshelfWaitMsAverage,
        StartupRequestBookmarkMsAverage,
        StartupRequestBookshelfMsAverage,
        StartupRequestBookmarkQueueMsAverage,
        StartupRequestBookshelfQueueMsAverage

    $summary | Format-Table -AutoSize

    $baseline = $results | Where-Object { $_.Name -eq "trace-baseline" }
    $optimized = $results | Where-Object { $_.Name -eq "current-optimized" }

    $comparison = if ($baseline -and $optimized) {
        [pscustomobject]@{
            T3LoadedEndMsDelta = [math]::Round($optimized.T3LoadedEndMsAverage - $baseline.T3LoadedEndMsAverage, 1)
            T4ContentRenderedStartMsDelta = [math]::Round($optimized.T4ContentRenderedStartMsAverage - $baseline.T4ContentRenderedStartMsAverage, 1)
            T5ViewModelEndMsDelta = [math]::Round($optimized.T5ViewModelEndMsAverage - $baseline.T5ViewModelEndMsAverage, 1)
            ContentRenderedEndMsDelta = [math]::Round($optimized.ContentRenderedEndMsAverage - $baseline.ContentRenderedEndMsAverage, 1)
            LoadedAsyncDurationMsDelta = [math]::Round($optimized.LoadedAsyncDurationMsAverage - $baseline.LoadedAsyncDurationMsAverage, 1)
            LoadedAsyncTailMsDelta = if ($null -eq $baseline.LoadedAsyncTailMsAverage -or $null -eq $optimized.LoadedAsyncTailMsAverage) { $null } else { [math]::Round($optimized.LoadedAsyncTailMsAverage - $baseline.LoadedAsyncTailMsAverage, 1) }
            WorkingSetMBDelta = [math]::Round($optimized.WorkingSetMBAverage - $baseline.WorkingSetMBAverage, 1)
            PrivateMemoryMBDelta = [math]::Round($optimized.PrivateMemoryMBAverage - $baseline.PrivateMemoryMBAverage, 1)
        }
    }

    $jsonPath = Join-Path $OutputRoot "results.json"
    [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("s")
        BaselineRef = $BaselineRef
        RunCount = $RunCount
        SeedProfilePath = $SeedProfilePath
        Summary = $summary
        Comparison = $comparison
        Results = $results
    } | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 $jsonPath

    Write-Host ""
    Write-Host "Results saved to $jsonPath" -ForegroundColor Green
}
finally {
    if (Test-Path $baselineWorktree) {
        Remove-Item $baselineWorktree -Recurse -Force -ErrorAction SilentlyContinue
    }
}
