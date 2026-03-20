Param(
    [ValidateSet("Release")][string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [Alias("Runs")][int]$RunCount = 5,
    [string]$BaselineRef = "HEAD",
    [string]$OutputRoot = "",
    [string]$SeedProfilePath = "",
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

    $currentAppPath = Join-Path $solutionDir "NeeView\App.xaml.cs"
    $currentMainWindowPath = Join-Path $solutionDir "NeeView\MainWindow\MainWindow.xaml.cs"
    $currentMainWindowModelPath = Join-Path $solutionDir "NeeView\MainWindow\MainWindowModel.cs"

    Copy-Item $currentAppPath (Join-Path $WorktreePath "NeeView\App.xaml.cs") -Force
    Copy-Item $currentMainWindowPath (Join-Path $WorktreePath "NeeView\MainWindow\MainWindow.xaml.cs") -Force

    $baselineModel = Get-Content -Raw $currentMainWindowModelPath

    $restoreBlock = @"
            using (App.Current.TraceStartupScope("MainWindowModel.LoadedAsync.CustomLayoutPanelManager.Restore"))
            {
                CustomLayoutPanelManager.Current.Restore();
            }

"@

    $susieBlock = @"
            using (App.Current.TraceStartupScope("MainWindowModel.LoadedAsync.SusiePluginManager.Initialize"))
            {
                SusiePluginManager.Current.Initialize();
            }

"@

    if (-not $baselineModel.Contains($restoreBlock)) {
        throw "Cannot find restore block in MainWindowModel.cs while creating baseline workspace."
    }

    $baselineModel = $baselineModel.Replace($restoreBlock, $restoreBlock + $susieBlock)

    $optimizedWarmupBlock = @"
            _ = WarmupStartupPanelsAsync();

            using (App.Current.TraceStartupScope("MainWindowModel.LoadedAsync.UserSettingTools.ApplyDeferredCommandCollection"))
            {
                UserSettingTools.ApplyDeferredCommandCollection();
            }

"@

    $baselineWaitBlock = @"
            using (App.Current.TraceStartupScope("MainWindowModel.LoadedAsync.BookmarkFolderList.WaitAsync"))
            {
                await BookmarkFolderList.Current.WaitAsync(CancellationToken.None);
            }

            using (App.Current.TraceStartupScope("MainWindowModel.LoadedAsync.BookshelfFolderList.WaitAsync"))
            {
                await BookshelfFolderList.Current.WaitAsync(CancellationToken.None);
            }

"@

    if (-not $baselineModel.Contains($optimizedWarmupBlock)) {
        throw "Cannot find optimized warmup block in MainWindowModel.cs while creating baseline workspace."
    }

    $baselineModel = $baselineModel.Replace($optimizedWarmupBlock, $baselineWaitBlock)

    Write-GitTextFile -Ref $Ref -RepoRelativePath "NeeView/Command/CommandTable.cs" -DestinationPath (Join-Path $WorktreePath "NeeView\Command\CommandTable.cs")
    Write-GitTextFile -Ref $Ref -RepoRelativePath "NeeView/SaveData/UserSettingTools.cs" -DestinationPath (Join-Path $WorktreePath "NeeView\SaveData\UserSettingTools.cs")
    Write-GitTextFile -Ref $Ref -RepoRelativePath "NeeView/Setting/SettingPageFileTypes.cs" -DestinationPath (Join-Path $WorktreePath "NeeView\Setting\SettingPageFileTypes.cs")
    Write-GitTextFile -Ref $Ref -RepoRelativePath "NeeView/Susie/Client/SusiePluginManager.cs" -DestinationPath (Join-Path $WorktreePath "NeeView\Susie\Client\SusiePluginManager.cs")
    Set-Content -Path (Join-Path $WorktreePath "NeeView\MainWindow\MainWindowModel.cs") -Value $baselineModel -Encoding UTF8
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

    if (-not $TraceEntries.ContainsKey($Label)) {
        return $null
    }

    $entry = $TraceEntries[$Label]
    if (-not $entry.ContainsKey($Key)) {
        return $null
    }

    return [double]$entry[$Key]
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
        $trace = Wait-TraceMetrics -LogPath $logPath -RequiredLabelKeys $requiredLabels
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

    $result = [ordered]@{
        T3LoadedEndMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.Loaded" -Key "end_ms"), 1)
        T4ContentRenderedStartMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.ContentRendered" -Key "start_ms"), 1)
        T5ViewModelEndMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.ContentRendered.ViewModel" -Key "end_ms"), 1)
        ContentRenderedEndMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindow.ContentRendered" -Key "end_ms"), 1)
        LoadedAsyncDurationMs = [math]::Round((Get-TraceMetricValue -TraceEntries $trace -Label "MainWindowModel.LoadedAsync" -Key "duration_ms"), 1)
        WorkingSetMB = $workingSetMB
        PrivateMemoryMB = $privateMemoryMB
        Trace = $trace
        LogPath = $logPath
    }

    return [pscustomobject]$result
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
    Copy-DirectoryContents -Source $BaseProfileTemplate -Destination $warmupProfile

    Write-Host "[$($Variant.Name)] Warmup" -ForegroundColor DarkYellow
    $null = Start-TraceRun -Variant $Variant -ProfileDir $warmupProfile

    New-CleanDirectory $warmedTemplate
    Copy-DirectoryContents -Source $warmupProfile -Destination $warmedTemplate

    $runs = @()
    for ($i = 1; $i -le $script:RunCount; $i++) {
        $runProfile = Join-Path $variantRoot "run-$i"
        New-CleanDirectory $runProfile
        Copy-DirectoryContents -Source $warmedTemplate -Destination $runProfile

        Write-Host "[$($Variant.Name)] Run $i/$($script:RunCount)" -ForegroundColor Yellow
        $runs += Start-TraceRun -Variant $Variant -ProfileDir $runProfile
    }

    $t3Average = ($runs | Measure-Object -Property T3LoadedEndMs -Average).Average
    $t4Average = ($runs | Measure-Object -Property T4ContentRenderedStartMs -Average).Average
    $t5Average = ($runs | Measure-Object -Property T5ViewModelEndMs -Average).Average
    $contentRenderedAverage = ($runs | Measure-Object -Property ContentRenderedEndMs -Average).Average
    $loadedAsyncAverage = ($runs | Measure-Object -Property LoadedAsyncDurationMs -Average).Average
    $workingSetAverage = ($runs | Measure-Object -Property WorkingSetMB -Average).Average
    $privateAverage = ($runs | Measure-Object -Property PrivateMemoryMB -Average).Average

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
        WorkingSetMBAverage = [math]::Round($workingSetAverage, 1)
        PrivateMemoryMBAverage = [math]::Round($privateAverage, 1)
        SusieInitializeDurationMsAverage = if ($null -eq $susieAverage) { $null } else { [math]::Round($susieAverage, 1) }
        LoadedBookmarkWaitMsAverage = if ($null -eq $bookmarkWaitAverage) { $null } else { [math]::Round($bookmarkWaitAverage, 1) }
        LoadedBookshelfWaitMsAverage = if ($null -eq $bookshelfWaitAverage) { $null } else { [math]::Round($bookshelfWaitAverage, 1) }
        WarmupBookmarkWaitMsAverage = if ($null -eq $warmupBookmarkAverage) { $null } else { [math]::Round($warmupBookmarkAverage, 1) }
        WarmupBookshelfWaitMsAverage = if ($null -eq $warmupBookshelfAverage) { $null } else { [math]::Round($warmupBookshelfAverage, 1) }
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
        WorkingSetMBAverage,
        PrivateMemoryMBAverage,
        SusieInitializeDurationMsAverage,
        LoadedBookmarkWaitMsAverage,
        LoadedBookshelfWaitMsAverage,
        WarmupBookmarkWaitMsAverage,
        WarmupBookshelfWaitMsAverage

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
