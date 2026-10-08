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

function Get-NormalizedFullPath {
    param([string]$Path)

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $PathRoot = [System.IO.Path]::GetPathRoot($FullPath)
    $Separators = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )

    if ($FullPath.Length -gt $PathRoot.Length) {
        $FullPath = $FullPath.TrimEnd($Separators)
    }

    return $FullPath
}

try {
    $Downloads = Get-NormalizedFullPath -Path $Downloads
}
catch {
    Write-Host "Downloads path is invalid: $Downloads" -ForegroundColor Red
    exit 1
}

if (!(Test-Path -LiteralPath $Downloads -PathType Container)) {
    Write-Host "Downloads folder not found: $Downloads" -ForegroundColor Red
    exit 1
}

if (
    $null -eq $Config.categories -or
    $Config.categories -isnot [System.Management.Automation.PSCustomObject]
) {
    Write-Host "config.json must contain a categories object." -ForegroundColor Red
    exit 1
}

$InvalidCategoryCharacters = [System.IO.Path]::GetInvalidFileNameChars()
foreach ($Category in $Config.categories.PSObject.Properties) {
    $FolderName = [string]$Category.Name

    if (
        [string]::IsNullOrWhiteSpace($FolderName) -or
        $FolderName -in @(".", "..") -or
        $FolderName.Contains("\") -or
        $FolderName.Contains("/") -or
        $FolderName.Trim() -ne $FolderName -or
        $FolderName.EndsWith(".") -or
        $FolderName.IndexOfAny($InvalidCategoryCharacters) -ge 0 -or
        $FolderName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
    ) {
        Write-Host "Invalid category folder name in config.json: '$FolderName'" -ForegroundColor Red
        exit 1
    }
}

function Test-IsDownloadsRootFile {
    param([string]$Path)

    try {
        $FullPath = Get-NormalizedFullPath -Path $Path
        $ParentPath = Get-NormalizedFullPath -Path ([System.IO.Path]::GetDirectoryName($FullPath))

        return [string]::Equals(
            $ParentPath,
            $Downloads,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {
        return $false
    }
}

function Write-Log {
    param([string]$Message)

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "[$Timestamp] $Message"

    Add-Content -LiteralPath $LogPath -Value $Entry
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
        return "Skipped"
    }

    if (!(Test-Path -LiteralPath $File.FullName)) {
        return "Skipped"
    }

    if (!(Test-IsDownloadsRootFile -Path $File.FullName)) {
        Write-Log "Skipped '$($File.Name)' - file is outside the configured Downloads root."
        return "Skipped"
    }

    if ($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Log "Skipped '$($File.Name)' - reparse-point files are not moved."
        return "Skipped"
    }

    $Extension = $File.Extension.ToLowerInvariant()
    $Category = Get-Category -Extension $Extension

    if (!$Category) {
        Write-Log "Skipped '$($File.Name)' - no matching category."
        return "Skipped"
    }

    $DestinationDirectory = Join-Path $Downloads $Category

    if (Test-Path -LiteralPath $DestinationDirectory) {
        $DestinationItem = Get-Item -LiteralPath $DestinationDirectory -Force

        if (
            !$DestinationItem.PSIsContainer -or
            ($DestinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        ) {
            Write-Log "Skipped '$($File.Name)' - destination is not a safe category folder."
            return "Skipped"
        }
    }
    else {

        if ($DryRun) {
            Write-Host "[DRY RUN] Create folder: $DestinationDirectory"
        }
        else {
            [System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null

            Write-Log "Created folder: $Category"
        }
    }

    if ($DryRun) {

        Write-Host "[DRY RUN] $($File.Name) -> $Category"
        return "DryRun"
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
        return "Moved"

    }
    catch {

        Write-Log "ERROR moving '$($File.Name)': $($_.Exception.Message)"
        return "Failed"
    }
}

Write-Log "Organizer started. DryRun=$DryRun"

# -----------------------------------
# Single-file mode
# Used by Watch-Downloads.ps1
# -----------------------------------

if ($FilePath) {

    if (!(Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-Log "File no longer exists: $FilePath"
        exit 0
    }

    if (!(Test-IsDownloadsRootFile -Path $FilePath)) {
        Write-Log "Rejected file outside the configured Downloads root: $FilePath"
        exit 1
    }

    $Item = Get-Item -LiteralPath $FilePath

    if ($Item.PSIsContainer) {
        Write-Log "Skipped directory: $FilePath"
        exit 0
    }

    $MoveResult = Move-DownloadFile -File $Item

    Write-Log "Organizer finished."

    if ($MoveResult -eq "Failed") {
        exit 2
    }

    exit 0
}

# -----------------------------------
# Full Downloads organization mode
# -----------------------------------

foreach ($Category in $Config.categories.PSObject.Properties) {

    $FolderName = $Category.Name
    $DestinationFolder = Join-Path $Downloads $FolderName

    if (!(Test-Path -LiteralPath $DestinationFolder)) {

        if ($DryRun) {
            Write-Host "[DRY RUN] Create folder: $DestinationFolder"
        }
        else {
            [System.IO.Directory]::CreateDirectory($DestinationFolder) | Out-Null

            Write-Log "Created folder: $FolderName"
        }
    }
}

$Files = Get-ChildItem -LiteralPath $Downloads -File

foreach ($File in $Files) {
    $null = Move-DownloadFile -File $File
}

Write-Log "Organizer finished."
