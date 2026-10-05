$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$OrganizerPath = Join-Path $ScriptDir "Organize-Downloads.ps1"
$LogPath = Join-Path $ScriptDir "organizer.log"

if (!(Test-Path $ConfigPath)) {
    Write-Host "config.json was not found." -ForegroundColor Red
    exit 1
}

if (!(Test-Path $OrganizerPath)) {
    Write-Host "Organize-Downloads.ps1 was not found." -ForegroundColor Red
    exit 1
}

$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$Downloads = if ($Config.downloadsPath) {
    [Environment]::ExpandEnvironmentVariables($Config.downloadsPath)
}
else {
    Join-Path $env:USERPROFILE "Downloads"
}

if (!(Test-Path $Downloads)) {
    Write-Host "Downloads folder not found: $Downloads" -ForegroundColor Red
    exit 1
}

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$Timestamp] $Message"
}

function Test-FileReady {
    param(
        [string]$Path,
        [int]$Attempts = 60,
        [int]$DelayMilliseconds = 1000
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
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    return $false
}

$IgnoredExtensions = @(
    ".crdownload",
    ".part",
    ".partial",
    ".tmp",
    ".download"
)

$Watcher = New-Object System.IO.FileSystemWatcher

$Watcher.Path = $Downloads
$Watcher.Filter = "*"
$Watcher.IncludeSubdirectories = $false
$Watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite'
$Watcher.EnableRaisingEvents = $true

Write-Host ""
Write-Host "AutoDownloadsOrganizer V3" -ForegroundColor Cyan
Write-Host "Watching: $Downloads" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

Write-Log "Real-time watcher started."

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

        if ((Get-Item -LiteralPath $Path).PSIsContainer) {
            continue
        }

        $Extension = [System.IO.Path]::GetExtension($Path).ToLower()

        if ($IgnoredExtensions -contains $Extension) {
            continue
        }

        Write-Host "Detected: $($Result.Name)" -ForegroundColor Yellow
        Write-Host "Waiting for download to finish..." -ForegroundColor DarkGray

        if (Test-FileReady -Path $Path) {

            # Small delay to avoid moving a file while the browser
            # is still doing final rename/write operations.
            Start-Sleep -Milliseconds 500

            Write-Host "Organizing..." -ForegroundColor Gray

            try {

                & $OrganizerPath

                Write-Host "Done." -ForegroundColor Green
                Write-Host ""

            }
            catch {

                Write-Host "Organizer failed: $($_.Exception.Message)" `
                    -ForegroundColor Red

                Write-Log "Organizer failed: $($_.Exception.Message)"

            }

        }
        else {

            Write-Host "File was not ready: $($Result.Name)" `
                -ForegroundColor Red

            Write-Log "File was not ready: $($Result.Name)"
        }
    }

}
finally {

    $Watcher.EnableRaisingEvents = $false
    $Watcher.Dispose()

    Write-Log "Real-time watcher stopped."

    Write-Host ""
    Write-Host "Watcher stopped." -ForegroundColor Yellow
}