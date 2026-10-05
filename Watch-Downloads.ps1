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

if (!(Test-Path $ConfigPath)) {
    Write-Host "config.json was not found." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

if (!(Test-Path $OrganizerPath)) {
    Write-Host "Organize-Downloads.ps1 was not found." -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
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

if (!(Test-Path $Downloads)) {
    Write-Host "Downloads folder not found: $Downloads" -ForegroundColor Red
    $Mutex.Dispose()
    exit 1
}

# ------------------------------------------------
# Settings
# ------------------------------------------------

$WaitMilliseconds = 1000

if ($Config.watcher -and $Config.watcher.checkIntervalMilliseconds) {
    $WaitMilliseconds = [int]$Config.watcher.checkIntervalMilliseconds
}

$PostReadyDelayMilliseconds = 500

if ($Config.watcher -and $Config.watcher.postReadyDelayMilliseconds) {
    $PostReadyDelayMilliseconds =
        [int]$Config.watcher.postReadyDelayMilliseconds
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
        -Path $LogPath `
        -Value "[$Timestamp] [Watcher] $Message"
}

# ------------------------------------------------
# Wait until a file is finished being written
# ------------------------------------------------

function Test-FileReady {
    param(
        [string]$Path,
        [int]$Attempts = 60
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
# FileSystemWatcher
# ------------------------------------------------

$Watcher = New-Object System.IO.FileSystemWatcher

$Watcher.Path = $Downloads
$Watcher.Filter = "*"
$Watcher.IncludeSubdirectories = $false

$Watcher.NotifyFilter = (
    [System.IO.NotifyFilters]::FileName -bor
    [System.IO.NotifyFilters]::LastWrite
)

$Watcher.EnableRaisingEvents = $true

Write-Host ""
Write-Host "AutoDownloadsOrganizer V4" -ForegroundColor Cyan
Write-Host "Watching: $Downloads" -ForegroundColor Gray
Write-Host "Single-instance protection: Enabled" -ForegroundColor DarkGray
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

Write-WatcherLog "V4 watcher started."

try {

    while ($true) {

        $Result = $Watcher.WaitForChanged(
            [System.IO.WatcherChangeTypes]'Created, Renamed',
            1000
        )

        if ($Result.TimedOut) {
            continue
        }

        $Path = Join-Path $Downloads $Result.Name

        if (!(Test-Path -LiteralPath $Path)) {
            continue
        }

        $Item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue

        if (!$Item) {
            continue
        }

        if ($Item.PSIsContainer) {
            continue
        }

        $Extension = $Item.Extension.ToLower()

        if ($IgnoredExtensions -contains $Extension) {
            continue
        }

        if (Test-RecentlyProcessed -Path $Path) {
            continue
        }

        Write-Host "Detected: $($Item.Name)" -ForegroundColor Yellow
        Write-Host "Waiting for download to finish..." `
            -ForegroundColor DarkGray

        if (!(Test-FileReady -Path $Path)) {

            Write-Host "File was not ready: $($Item.Name)" `
                -ForegroundColor Red

            Write-WatcherLog `
                "File was not ready: $($Item.Name)"

            continue
        }

        Start-Sleep `
            -Milliseconds $PostReadyDelayMilliseconds

        if (!(Test-Path -LiteralPath $Path)) {
            continue
        }

        Write-Host "Organizing..." -ForegroundColor Gray

        try {

            & $OrganizerPath -FilePath $Path

            Write-Host "Done." -ForegroundColor Green
            Write-Host ""

        }
        catch {

            Write-Host `
                "Organizer failed: $($_.Exception.Message)" `
                -ForegroundColor Red

            Write-WatcherLog `
                "Organizer failed: $($_.Exception.Message)"
        }
    }
}
finally {

    $Watcher.EnableRaisingEvents = $false
    $Watcher.Dispose()

    Write-WatcherLog "V4 watcher stopped."

    try {
        $Mutex.ReleaseMutex()
    }
    catch {
    }

    $Mutex.Dispose()

    Write-Host ""
    Write-Host "Watcher stopped." -ForegroundColor Yellow
}