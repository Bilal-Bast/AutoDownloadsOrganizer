param(
    [switch]$DryRun,

    [string]$FilePath
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogPath = Join-Path $ScriptDir "organizer.log"

if (!(Test-Path $ConfigPath)) {
    Write-Host "config.json was not found." -ForegroundColor Red
    exit 1
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Host "config.json could not be read." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
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
    exit 1
}

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] $Message"

    Add-Content -Path $LogPath -Value $Entry
    Write-Host $Entry
}

function Get-UniqueDestination {
    param(
        [string]$Directory,
        [string]$FileName
    )

    $Target = Join-Path $Directory $FileName

    if (!(Test-Path -LiteralPath $Target)) {
        return $Target
    }

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $Extension = [System.IO.Path]::GetExtension($FileName)

    $Counter = 1

    do {
        $NewName = "$BaseName ($Counter)$Extension"
        $Target = Join-Path $Directory $NewName
        $Counter++
    }
    while (Test-Path -LiteralPath $Target)

    return $Target
}

function Get-Category {
    param([string]$Extension)

    foreach ($Category in $Config.categories.PSObject.Properties) {

        if ($Category.Name -eq "Other") {
            continue
        }

        if ($Category.Value -contains $Extension) {
            return $Category.Name
        }
    }

    if ($Config.moveUnknownFiles) {
        return "Other"
    }

    return $null
}

function Move-DownloadFile {
    param(
        [System.IO.FileInfo]$File
    )

    if (!$File) {
        return
    }

    if (!(Test-Path -LiteralPath $File.FullName)) {
        return
    }

    $Extension = $File.Extension.ToLower()
    $Category = Get-Category -Extension $Extension

    if (!$Category) {
        Write-Log "Skipped '$($File.Name)' - no matching category."
        return
    }

    $DestinationDirectory = Join-Path $Downloads $Category

    if (!(Test-Path $DestinationDirectory)) {

        if ($DryRun) {
            Write-Host "[DRY RUN] Create folder: $DestinationDirectory"
        }
        else {
            New-Item `
                -ItemType Directory `
                -Path $DestinationDirectory `
                -Force | Out-Null

            Write-Log "Created folder: $Category"
        }
    }

    if ($DryRun) {

        Write-Host "[DRY RUN] $($File.Name) -> $Category"
        return
    }

    $Destination = Get-UniqueDestination `
        -Directory $DestinationDirectory `
        -FileName $File.Name

    try {

        Move-Item `
            -LiteralPath $File.FullName `
            -Destination $Destination `
            -ErrorAction Stop

        Write-Log "Moved '$($File.Name)' -> '$Category'"

    }
    catch {

        Write-Log "ERROR moving '$($File.Name)': $($_.Exception.Message)"
    }
}

Write-Log "Organizer started. DryRun=$DryRun"

# -----------------------------------
# Single-file mode
# Used by Watch-Downloads.ps1
# -----------------------------------

if ($FilePath) {

    if (!(Test-Path -LiteralPath $FilePath)) {
        Write-Log "File no longer exists: $FilePath"
        exit 0
    }

    $Item = Get-Item -LiteralPath $FilePath

    if ($Item.PSIsContainer) {
        Write-Log "Skipped directory: $FilePath"
        exit 0
    }

    Move-DownloadFile -File $Item

    Write-Log "Organizer finished."
    exit 0
}

# -----------------------------------
# Full Downloads organization mode
# -----------------------------------

foreach ($Category in $Config.categories.PSObject.Properties) {

    $FolderName = $Category.Name
    $DestinationFolder = Join-Path $Downloads $FolderName

    if (!(Test-Path $DestinationFolder)) {

        if ($DryRun) {
            Write-Host "[DRY RUN] Create folder: $DestinationFolder"
        }
        else {
            New-Item `
                -ItemType Directory `
                -Path $DestinationFolder `
                -Force | Out-Null

            Write-Log "Created folder: $FolderName"
        }
    }
}

$Files = Get-ChildItem -Path $Downloads -File

foreach ($File in $Files) {
    Move-DownloadFile -File $File
}

Write-Log "Organizer finished."