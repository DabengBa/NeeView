Param(
    [ValidateSet("Release")][string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [Alias("Runs")][int]$RunCount = 20,
    [string]$BaselineRef = "HEAD",
    [string]$OutputRoot = "",
    [string]$SeedProfilePath = "",
    [int]$TraceTimeoutSeconds = 90,
    [int]$TraceRetryCount = 1,
    [double]$TrimRatio = 0.1,
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

function Test-IsTraceTimeoutException {
    param([System.Exception]$Exception)

    if ($null -eq $Exception) {
        return $false
    }

    return $Exception.Message -like "Timed out waiting for startup trace metrics*"
}

function Get-PercentileValue {
    param(
        [double[]]$SortedValues,
        [double]$Percentile
    )

    if ($null -eq $SortedValues -or $SortedValues.Count -eq 0) {
        return $null
    }

    if ($SortedValues.Count -eq 1) {
        return $SortedValues[0]
    }

    $clampedPercentile = [Math]::Min([Math]::Max($Percentile, 0.0), 100.0)
    $rank = ($clampedPercentile / 100.0) * ($SortedValues.Count - 1)
    $lowerIndex = [int][Math]::Floor($rank)
    $upperIndex = [int][Math]::Ceiling($rank)

    if ($lowerIndex -eq $upperIndex) {
        return $SortedValues[$lowerIndex]
    }

    $weight = $rank - $lowerIndex
    return $SortedValues[$lowerIndex] + (($SortedValues[$upperIndex] - $SortedValues[$lowerIndex]) * $weight)
}

function Get-NumericStats {
    param(
        [object[]]$Values,
        [double]$TrimRatio = 0.1
    )

    $sortedValues = @(
        $Values |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [double]$_ } |
            Sort-Object
    )

    if ($sortedValues.Count -eq 0) {
        return [pscustomobject]@{
            Count = 0
            Average = $null
            Median = $null
            TrimmedMean = $null
            P90 = $null
            Max = $null
        }
    }

    $trimCount = [int][Math]::Floor($sortedValues.Count * $TrimRatio)
    $trimmedValues =
        if (($trimCount * 2) -lt $sortedValues.Count) {
            @($sortedValues[$trimCount..($sortedValues.Count - $trimCount - 1)])
        }
        else {
            $sortedValues
        }

    $average = ($sortedValues | Measure-Object -Average).Average
    $trimmedMean = ($trimmedValues | Measure-Object -Average).Average

    return [pscustomobject]@{
        Count = $sortedValues.Count
        Average = Convert-ToRoundedNullable -Value $average
        Median = Convert-ToRoundedNullable -Value (Get-PercentileValue -SortedValues $sortedValues -Percentile 50)
        TrimmedMean = Convert-ToRoundedNullable -Value $trimmedMean
        P90 = Convert-ToRoundedNullable -Value (Get-PercentileValue -SortedValues $sortedValues -Percentile 90)
        Max = Convert-ToRoundedNullable -Value $sortedValues[-1]
    }
}

function Get-RunPropertyStats {
    param(
        [object[]]$Runs,
        [string]$PropertyName
    )

    $values = @(
        $Runs |
            ForEach-Object {
                $value = $_.$PropertyName
                if ($null -ne $value) { $value }
            }
    )

    return Get-NumericStats -Values $values -TrimRatio $TrimRatio
}

function Get-RunTraceMetricStats {
    param(
        [object[]]$Runs,
        [string]$Label,
        [string]$Key
    )

    $values = @(
        $Runs |
            ForEach-Object {
                $value = Get-TraceMetricValue -TraceEntries $_.Trace -Label $Label -Key $Key
                if ($null -ne $value) { $value }
            }
    )

    return Get-NumericStats -Values $values -TrimRatio $TrimRatio
}

function Add-StatsProperties {
    param(
        [System.Collections.IDictionary]$Target,
        [string]$Prefix,
        [pscustomobject]$Stats
    )

    $Target["${Prefix}SampleCount"] = $Stats.Count
    $Target["${Prefix}Average"] = $Stats.Average
    $Target["${Prefix}Median"] = $Stats.Median
    $Target["${Prefix}TrimmedMean"] = $Stats.TrimmedMean
    $Target["${Prefix}P90"] = $Stats.P90
    $Target["${Prefix}Max"] = $Stats.Max
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
    $psi.Arguments = "--blank --new-window=on --reset-placement"
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
        T0ToT3Ms = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.Loaded" -Key "end_ms"), 1)
        T3ToT4Ms = [math]::Round((Get-TraceMetricDelta -TraceEntries $trace -StartLabel "MainWindow.Loaded" -StartKey "end_ms" -EndLabel "MainWindow.ContentRendered" -EndKey "start_ms"), 1)
        T4ToT5Ms = [math]::Round((Get-TraceMetricDelta -TraceEntries $trace -StartLabel "MainWindow.ContentRendered" -StartKey "start_ms" -EndLabel "MainWindow.ContentRendered.ViewModel" -EndKey "end_ms"), 1)
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
    $timeoutAttemptCount = 0
    $failureAttemptCount = 0
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        New-CleanDirectory $ProfileDir
        Copy-DirectoryContents -Source $SeedProfileDir -Destination $ProfileDir

        $attemptSuffix = if ($maxAttempts -gt 1) { " (attempt $attempt/$maxAttempts)" } else { "" }
        Write-Host "$DisplayName$attemptSuffix" -ForegroundColor Yellow

        try {
            $run = Start-TraceRun -Variant $Variant -ProfileDir $ProfileDir
            $run | Add-Member -NotePropertyName AttemptCount -NotePropertyValue $attempt
            $run | Add-Member -NotePropertyName TimeoutAttemptCount -NotePropertyValue $timeoutAttemptCount
            $run | Add-Member -NotePropertyName FailureAttemptCount -NotePropertyValue $failureAttemptCount
            $run | Add-Member -NotePropertyName HadTimeoutRetry -NotePropertyValue ($timeoutAttemptCount -gt 0)
            return $run
        }
        catch {
            $failureAttemptCount++
            if (Test-IsTraceTimeoutException -Exception $_.Exception) {
                $timeoutAttemptCount++
            }

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

    $runCountActual = $runs.Count
    $totalAttemptCount = ($runs | Measure-Object -Property AttemptCount -Sum).Sum
    $failureAttemptCount = ($runs | Measure-Object -Property FailureAttemptCount -Sum).Sum
    $timeoutAttemptCount = ($runs | Measure-Object -Property TimeoutAttemptCount -Sum).Sum
    $timeoutRunCount = @($runs | Where-Object { $_.HadTimeoutRetry }).Count

    if ($null -eq $totalAttemptCount) { $totalAttemptCount = 0 }
    if ($null -eq $failureAttemptCount) { $failureAttemptCount = 0 }
    if ($null -eq $timeoutAttemptCount) { $timeoutAttemptCount = 0 }

    $t3Stats = Get-RunPropertyStats -Runs $runs -PropertyName "T3LoadedEndMs"
    $t4Stats = Get-RunPropertyStats -Runs $runs -PropertyName "T4ContentRenderedStartMs"
    $t5Stats = Get-RunPropertyStats -Runs $runs -PropertyName "T5ViewModelEndMs"
    $t0ToT3Stats = Get-RunPropertyStats -Runs $runs -PropertyName "T0ToT3Ms"
    $t3ToT4Stats = Get-RunPropertyStats -Runs $runs -PropertyName "T3ToT4Ms"
    $t4ToT5Stats = Get-RunPropertyStats -Runs $runs -PropertyName "T4ToT5Ms"
    $contentRenderedStats = Get-RunPropertyStats -Runs $runs -PropertyName "ContentRenderedEndMs"
    $loadedAsyncStats = Get-RunPropertyStats -Runs $runs -PropertyName "LoadedAsyncDurationMs"
    $loadedAsyncTailStats = Get-RunPropertyStats -Runs $runs -PropertyName "LoadedAsyncTailMs"
    $loadedAsyncResumeGapStats = Get-RunPropertyStats -Runs $runs -PropertyName "LoadedAsyncResumeGapMs"
    $workingSetStats = Get-RunPropertyStats -Runs $runs -PropertyName "WorkingSetMB"
    $privateMemoryStats = Get-RunPropertyStats -Runs $runs -PropertyName "PrivateMemoryMB"
    $startupRequestBookmarkStats = Get-RunPropertyStats -Runs $runs -PropertyName "StartupRequestBookmarkMs"
    $startupRequestBookshelfStats = Get-RunPropertyStats -Runs $runs -PropertyName "StartupRequestBookshelfMs"
    $startupRequestBookmarkQueueStats = Get-RunPropertyStats -Runs $runs -PropertyName "StartupRequestBookmarkQueueMs"
    $startupRequestBookshelfQueueStats = Get-RunPropertyStats -Runs $runs -PropertyName "StartupRequestBookshelfQueueMs"

    $susieStats = Get-RunTraceMetricStats -Runs $runs -Label "MainWindowModel.LoadedAsync.SusiePluginManager.Initialize" -Key "duration_ms"
    $bookmarkWaitStats = Get-RunTraceMetricStats -Runs $runs -Label "MainWindowModel.LoadedAsync.BookmarkFolderList.WaitAsync" -Key "duration_ms"
    $bookshelfWaitStats = Get-RunTraceMetricStats -Runs $runs -Label "MainWindowModel.LoadedAsync.BookshelfFolderList.WaitAsync" -Key "duration_ms"
    $warmupBookmarkStats = Get-RunTraceMetricStats -Runs $runs -Label "MainWindowModel.StartupWarmup.BookmarkFolderList.WaitAsync" -Key "duration_ms"
    $warmupBookshelfStats = Get-RunTraceMetricStats -Runs $runs -Label "MainWindowModel.StartupWarmup.BookshelfFolderList.WaitAsync" -Key "duration_ms"

    $summary = [ordered]@{
        Name = $Variant.Name
        PublishReadyToRun = $Variant.PublishReadyToRun
        SizeBytes = $Variant.SizeBytes
        SizeMB = [math]::Round($Variant.SizeBytes / 1MB, 1)
        RunCountActual = $runCountActual
        TotalAttemptCount = $totalAttemptCount
        FailureAttemptCount = $failureAttemptCount
        TimeoutAttemptCount = $timeoutAttemptCount
        TimeoutRunCount = $timeoutRunCount
        TimeoutRunRatePct = if ($runCountActual -eq 0) { $null } else { [math]::Round(($timeoutRunCount / $runCountActual) * 100.0, 1) }
        TimeoutAttemptRatePct = if ($totalAttemptCount -eq 0) { $null } else { [math]::Round(($timeoutAttemptCount / $totalAttemptCount) * 100.0, 1) }
    }

    Add-StatsProperties -Target $summary -Prefix "T3LoadedEndMs" -Stats $t3Stats
    Add-StatsProperties -Target $summary -Prefix "T4ContentRenderedStartMs" -Stats $t4Stats
    Add-StatsProperties -Target $summary -Prefix "T5ViewModelEndMs" -Stats $t5Stats
    Add-StatsProperties -Target $summary -Prefix "T0ToT3Ms" -Stats $t0ToT3Stats
    Add-StatsProperties -Target $summary -Prefix "T3ToT4Ms" -Stats $t3ToT4Stats
    Add-StatsProperties -Target $summary -Prefix "T4ToT5Ms" -Stats $t4ToT5Stats
    Add-StatsProperties -Target $summary -Prefix "ContentRenderedEndMs" -Stats $contentRenderedStats
    Add-StatsProperties -Target $summary -Prefix "LoadedAsyncDurationMs" -Stats $loadedAsyncStats
    Add-StatsProperties -Target $summary -Prefix "LoadedAsyncTailMs" -Stats $loadedAsyncTailStats
    Add-StatsProperties -Target $summary -Prefix "LoadedAsyncResumeGapMs" -Stats $loadedAsyncResumeGapStats
    Add-StatsProperties -Target $summary -Prefix "WorkingSetMB" -Stats $workingSetStats
    Add-StatsProperties -Target $summary -Prefix "PrivateMemoryMB" -Stats $privateMemoryStats
    Add-StatsProperties -Target $summary -Prefix "SusieInitializeDurationMs" -Stats $susieStats
    Add-StatsProperties -Target $summary -Prefix "LoadedBookmarkWaitMs" -Stats $bookmarkWaitStats
    Add-StatsProperties -Target $summary -Prefix "LoadedBookshelfWaitMs" -Stats $bookshelfWaitStats
    Add-StatsProperties -Target $summary -Prefix "WarmupBookmarkWaitMs" -Stats $warmupBookmarkStats
    Add-StatsProperties -Target $summary -Prefix "WarmupBookshelfWaitMs" -Stats $warmupBookshelfStats
    Add-StatsProperties -Target $summary -Prefix "StartupRequestBookmarkMs" -Stats $startupRequestBookmarkStats
    Add-StatsProperties -Target $summary -Prefix "StartupRequestBookshelfMs" -Stats $startupRequestBookshelfStats
    Add-StatsProperties -Target $summary -Prefix "StartupRequestBookmarkQueueMs" -Stats $startupRequestBookmarkQueueStats
    Add-StatsProperties -Target $summary -Prefix "StartupRequestBookshelfQueueMs" -Stats $startupRequestBookshelfQueueStats

    $summary["Runs"] = $runs

    return [pscustomobject]$summary
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
        RunCountActual,
        TimeoutRunCount,
        TimeoutRunRatePct,
        TimeoutAttemptRatePct,
        T0ToT3MsMedian,
        T0ToT3MsTrimmedMean,
        T0ToT3MsP90,
        T0ToT3MsMax,
        T3ToT4MsMedian,
        T3ToT4MsTrimmedMean,
        T3ToT4MsP90,
        T3ToT4MsMax,
        T4ToT5MsMedian,
        T4ToT5MsTrimmedMean,
        T4ToT5MsP90,
        T4ToT5MsMax,
        LoadedAsyncDurationMsMedian,
        LoadedAsyncDurationMsTrimmedMean,
        LoadedAsyncDurationMsP90,
        LoadedAsyncDurationMsMax,
        LoadedAsyncTailMsMedian,
        LoadedAsyncTailMsP90,
        WorkingSetMBMedian,
        PrivateMemoryMBMedian

    $consoleSummary = $results | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            Runs = $_.RunCountActual
            TimeoutRunPct = $_.TimeoutRunRatePct
            TimeoutAttemptPct = $_.TimeoutAttemptRatePct
            T0ToT3Tm = $_.T0ToT3MsTrimmedMean
            T0ToT3P90 = $_.T0ToT3MsP90
            T0ToT3Max = $_.T0ToT3MsMax
            T3ToT4Tm = $_.T3ToT4MsTrimmedMean
            T3ToT4P90 = $_.T3ToT4MsP90
            T4ToT5Tm = $_.T4ToT5MsTrimmedMean
            T4ToT5P90 = $_.T4ToT5MsP90
            LoadedAsyncTm = $_.LoadedAsyncDurationMsTrimmedMean
            LoadedAsyncP90 = $_.LoadedAsyncDurationMsP90
            LoadedAsyncMax = $_.LoadedAsyncDurationMsMax
        }
    }

    $consoleSummary | Format-Table -AutoSize

    $baseline = $results | Where-Object { $_.Name -eq "trace-baseline" }
    $optimized = $results | Where-Object { $_.Name -eq "current-optimized" }

    $comparison = if ($baseline -and $optimized) {
        [pscustomobject]@{
            T0ToT3MsTrimmedMeanDelta = [math]::Round($optimized.T0ToT3MsTrimmedMean - $baseline.T0ToT3MsTrimmedMean, 1)
            T0ToT3MsP90Delta = [math]::Round($optimized.T0ToT3MsP90 - $baseline.T0ToT3MsP90, 1)
            T0ToT3MsMaxDelta = [math]::Round($optimized.T0ToT3MsMax - $baseline.T0ToT3MsMax, 1)
            T3ToT4MsTrimmedMeanDelta = [math]::Round($optimized.T3ToT4MsTrimmedMean - $baseline.T3ToT4MsTrimmedMean, 1)
            T3ToT4MsP90Delta = [math]::Round($optimized.T3ToT4MsP90 - $baseline.T3ToT4MsP90, 1)
            T4ToT5MsTrimmedMeanDelta = [math]::Round($optimized.T4ToT5MsTrimmedMean - $baseline.T4ToT5MsTrimmedMean, 1)
            T4ToT5MsP90Delta = [math]::Round($optimized.T4ToT5MsP90 - $baseline.T4ToT5MsP90, 1)
            LoadedAsyncDurationMsTrimmedMeanDelta = [math]::Round($optimized.LoadedAsyncDurationMsTrimmedMean - $baseline.LoadedAsyncDurationMsTrimmedMean, 1)
            LoadedAsyncDurationMsP90Delta = [math]::Round($optimized.LoadedAsyncDurationMsP90 - $baseline.LoadedAsyncDurationMsP90, 1)
            LoadedAsyncTailMsTrimmedMeanDelta = if ($null -eq $baseline.LoadedAsyncTailMsTrimmedMean -or $null -eq $optimized.LoadedAsyncTailMsTrimmedMean) { $null } else { [math]::Round($optimized.LoadedAsyncTailMsTrimmedMean - $baseline.LoadedAsyncTailMsTrimmedMean, 1) }
            WorkingSetMBMedianDelta = [math]::Round($optimized.WorkingSetMBMedian - $baseline.WorkingSetMBMedian, 1)
            PrivateMemoryMBMedianDelta = [math]::Round($optimized.PrivateMemoryMBMedian - $baseline.PrivateMemoryMBMedian, 1)
            TimeoutRunRatePctDelta = if ($null -eq $baseline.TimeoutRunRatePct -or $null -eq $optimized.TimeoutRunRatePct) { $null } else { [math]::Round($optimized.TimeoutRunRatePct - $baseline.TimeoutRunRatePct, 1) }
            TimeoutAttemptRatePctDelta = if ($null -eq $baseline.TimeoutAttemptRatePct -or $null -eq $optimized.TimeoutAttemptRatePct) { $null } else { [math]::Round($optimized.TimeoutAttemptRatePct - $baseline.TimeoutAttemptRatePct, 1) }
        }
    }

    $jsonPath = Join-Path $OutputRoot "results.json"
    [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("s")
        BaselineRef = $BaselineRef
        RunCount = $RunCount
        TrimRatio = $TrimRatio
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
