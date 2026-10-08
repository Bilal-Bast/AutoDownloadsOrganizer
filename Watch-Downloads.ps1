$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$OrganizerPath = Join-Path $ScriptDir "Organize-Downloads.ps1"
$LogPath = Join-Path $ScriptDir "organizer.log"

# ------------------------------------------------
# Prevent multiple watcher instances
# ------------------------------------------------

$MutexName = "Local\AutoDownloadsOrganizerWatcher"

$CreatedNew = $false

$Mutex = New-Object System.Threading.Mutex(
    $true,
    $MutexName,
    [ref]$CreatedNew
)

if (!$CreatedNew) {

    Write-Host ""
    Write-Host "AutoDownloadsOrganizer is already running." `
        -ForegroundColor Yellow

    Write-Host ""

    exit 0
}

# ------------------------------------------------
# Validation
# ------------------------------------------------

if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Host "config.json was not found." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

if (!(Test-Path -LiteralPath $OrganizerPath -PathType Leaf)) {
    Write-Host "Organize-Downloads.ps1 was not found." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

try {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Host "config.json could not be read." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

$Downloads = if ($Config.downloadsPath) {
    [Environment]::ExpandEnvironmentVariables($Config.downloadsPath)
}
else {
    Join-Path $env:USERPROFILE "Downloads"
}

try {
    $Downloads = [System.IO.Path]::GetFullPath($Downloads)
}
catch {
    Write-Host "Downloads path is invalid: $Downloads" -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

if (!(Test-Path -LiteralPath $Downloads -PathType Container)) {
    Write-Host "Downloads folder not found: $Downloads" -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

# ------------------------------------------------
# Settings
# ------------------------------------------------

$WaitMilliseconds = 1000

if (
    $Config.watcher -and
    $Config.watcher.PSObject.Properties["checkIntervalMilliseconds"]
) {
    $WaitMilliseconds = [int]$Config.watcher.checkIntervalMilliseconds
}

$PostReadyDelayMilliseconds = 500

if (
    $Config.watcher -and
    $Config.watcher.PSObject.Properties["postReadyDelayMilliseconds"]
) {
    $PostReadyDelayMilliseconds =
        [int]$Config.watcher.postReadyDelayMilliseconds
}

if ($WaitMilliseconds -lt 1 -or $WaitMilliseconds -gt 60000) {
    Write-Host "watcher.checkIntervalMilliseconds must be between 1 and 60000." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

if ($PostReadyDelayMilliseconds -lt 0 -or $PostReadyDelayMilliseconds -gt 60000) {
    Write-Host "watcher.postReadyDelayMilliseconds must be between 0 and 60000." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

$IgnoredExtensions = @(
    ".crdownload",
    ".part",
    ".partial",
    ".tmp",
    ".download"
)

# Stores recently processed paths so duplicate FileSystemWatcher
# events don't organize the same file twice.

$RecentlyProcessed = @{}

$DuplicateWindowSeconds = 5

# ------------------------------------------------
# Logging
# ------------------------------------------------

function Write-WatcherLog {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Add-Content `
        -LiteralPath $LogPath `
        -Value "[$Timestamp] [Watcher] $Message"
}

# ------------------------------------------------
# Wait until a file is finished being written
# ------------------------------------------------

function Test-FileReady {
    param(
        [string]$Path,
        [int]$Attempts = 5
    )

    for ($i = 0; $i -lt $Attempts; $i++) {

        if (!(Test-Path -LiteralPath $Path)) {
            return $false
        }

        try {

            $Stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::None
            )

            $Stream.Close()

            return $true

        }
        catch {

            Start-Sleep -Milliseconds $WaitMilliseconds
        }
    }

    return $false
}

# ------------------------------------------------
# Duplicate event protection
# ------------------------------------------------

function Test-RecentlyProcessed {
    param([string]$Path)

    $Now = Get-Date

    foreach ($Key in @($RecentlyProcessed.Keys)) {

        $Age = ($Now - $RecentlyProcessed[$Key]).TotalSeconds

        if ($Age -gt $DuplicateWindowSeconds) {
            $RecentlyProcessed.Remove($Key)
        }
    }

    if ($RecentlyProcessed.ContainsKey($Path)) {
        return $true
    }

    $RecentlyProcessed[$Path] = $Now

    return $false
}

# ------------------------------------------------
# FileSystemWatcher with an asynchronous work queue
# ------------------------------------------------

$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $Downloads
$Watcher.Filter = "*"
$Watcher.IncludeSubdirectories = $false
$Watcher.InternalBufferSize = 65536
$Watcher.NotifyFilter = (
    [System.IO.NotifyFilters]::FileName -bor
    [System.IO.NotifyFilters]::LastWrite -bor
    [System.IO.NotifyFilters]::Size
)

$PendingPaths = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$RescanToken = ([char]0).ToString() + "__AUTO_DOWNLOADS_ORGANIZER_RESCAN__"
$DeferredRetries = @{}
$EventPrefix = "AutoDownloadsOrganizerWatcher.$PID"
$EventSourceIdentifiers = @(
    "$EventPrefix.Created",
    "$EventPrefix.Changed",
    "$EventPrefix.Renamed",
    "$EventPrefix.Error"
)
$Subscriptions = @()
$RetryDelayMilliseconds = [Math]::Max(
    $WaitMilliseconds,
    (($DuplicateWindowSeconds + 1) * 1000)
)

try {
    $Subscriptions += Register-ObjectEvent `
        -InputObject $Watcher `
        -EventName Created `
        -SourceIdentifier $EventSourceIdentifiers[0] `
        -MessageData $PendingPaths `
        -Action {
            [void]$Event.MessageData.Enqueue([string]$Event.SourceEventArgs.FullPath)
        }

    $Subscriptions += Register-ObjectEvent `
        -InputObject $Watcher `
        -EventName Changed `
        -SourceIdentifier $EventSourceIdentifiers[1] `
        -MessageData $PendingPaths `
        -Action {
            [void]$Event.MessageData.Enqueue([string]$Event.SourceEventArgs.FullPath)
        }

    $Subscriptions += Register-ObjectEvent `
        -InputObject $Watcher `
        -EventName Renamed `
        -SourceIdentifier $EventSourceIdentifiers[2] `
        -MessageData $PendingPaths `
        -Action {
            [void]$Event.MessageData.Enqueue([string]$Event.SourceEventArgs.FullPath)
        }

    $Subscriptions += Register-ObjectEvent `
        -InputObject $Watcher `
        -EventName Error `
        -SourceIdentifier $EventSourceIdentifiers[3] `
        -MessageData $PendingPaths `
        -Action {
            [void]$Event.MessageData.Enqueue((([char]0).ToString() + "__AUTO_DOWNLOADS_ORGANIZER_RESCAN__"))
        }

    $Watcher.EnableRaisingEvents = $true

    Write-Host ""
    Write-Host "AutoDownloadsOrganizer V6" -ForegroundColor Cyan
    Write-Host "Watching: $Downloads" -ForegroundColor Gray
    Write-Host "Single-instance protection: Enabled" -ForegroundColor DarkGray
    Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
    Write-Host ""

    Write-WatcherLog "V6 watcher started."

    while ($true) {
        $Now = Get-Date

        foreach ($DeferredPath in @($DeferredRetries.Keys)) {
            if ($DeferredRetries[$DeferredPath] -le $Now) {
                [void]$DeferredRetries.Remove($DeferredPath)
                [void]$PendingPaths.Enqueue($DeferredPath)
            }
        }

        $Path = $null

        if (!$PendingPaths.TryDequeue([ref]$Path)) {
            Start-Sleep -Milliseconds 200
            continue
        }

        if ($Path -eq $RescanToken) {
            Write-WatcherLog "Filesystem watcher reported an error; rescanning Downloads root."

            try {
                $RescanFiles = Get-ChildItem `
                    -LiteralPath $Downloads `
                    -File `
                    -ErrorAction Stop

                foreach ($RescanFile in $RescanFiles) {
                    [void]$PendingPaths.Enqueue($RescanFile.FullName)
                }

                Write-WatcherLog "Recovery rescan queued $($RescanFiles.Count) file(s)."
            }
            catch {
                Write-WatcherLog "Recovery rescan failed: $($_.Exception.Message)"
            }

            continue
        }

        if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
            continue
        }

        if ($DeferredRetries.ContainsKey($Path)) {
            continue
        }

        $Item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue

        if (!$Item -or $Item.PSIsContainer) {
            continue
        }

        $Extension = $Item.Extension.ToLowerInvariant()

        if ($IgnoredExtensions -contains $Extension) {
            continue
        }

        if (Test-RecentlyProcessed -Path $Path) {
            continue
        }

        Write-Host "Detected: $($Item.Name)" -ForegroundColor Yellow
        Write-Host "Checking whether the file is ready..." -ForegroundColor DarkGray

        if (!(Test-FileReady -Path $Path)) {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                Write-Host "File is still busy; retry queued: $($Item.Name)" -ForegroundColor DarkYellow
                Write-WatcherLog "File is still busy; retry queued: $($Item.Name)"
                $DeferredRetries[$Path] = (Get-Date).AddMilliseconds($RetryDelayMilliseconds)
            }

            continue
        }

        if ($PostReadyDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $PostReadyDelayMilliseconds
        }

        if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
            continue
        }

        if (!(Test-FileReady -Path $Path -Attempts 1)) {
            $DeferredRetries[$Path] = (Get-Date).AddMilliseconds($RetryDelayMilliseconds)
            Write-WatcherLog "File became busy again; retry queued: $($Item.Name)"
            continue
        }

        Write-Host "Organizing..." -ForegroundColor Gray

        try {
            & $OrganizerPath -FilePath $Path

            if ($LASTEXITCODE -ne 0) {
                if ($LASTEXITCODE -eq 2 -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
                    $DeferredRetries[$Path] = (Get-Date).AddMilliseconds($RetryDelayMilliseconds)
                    Write-Host "Move failed; retry queued: $($Item.Name)" -ForegroundColor DarkYellow
                    Write-WatcherLog "Move failed; retry queued: $($Item.Name)"
                }
                else {
                    Write-WatcherLog "Organizer returned exit code $LASTEXITCODE for '$($Item.Name)'."
                }

                continue
            }

            Write-Host "Done." -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Host "Organizer failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-WatcherLog "Organizer failed: $($_.Exception.Message)"

            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                $DeferredRetries[$Path] = (Get-Date).AddMilliseconds($RetryDelayMilliseconds)
                Write-WatcherLog "Retry queued after organizer exception: $($Item.Name)"
            }
        }
    }
}
finally {
    $Watcher.EnableRaisingEvents = $false
    $Watcher.Dispose()

    foreach ($SourceIdentifier in $EventSourceIdentifiers) {
        try {
            Unregister-Event -SourceIdentifier $SourceIdentifier -ErrorAction SilentlyContinue
        }
        catch {
        }
    }

    foreach ($Subscription in $Subscriptions) {
        Remove-Job -Job $Subscription -Force -ErrorAction SilentlyContinue
    }

    Write-WatcherLog "V6 watcher stopped."

    try {
        $Mutex.ReleaseMutex()
    }
    catch {
    }

    $Mutex.Dispose()
    Write-Host ""
    Write-Host "Watcher stopped." -ForegroundColor Yellow
}
