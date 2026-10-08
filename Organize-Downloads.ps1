param(
    [switch]$DryRun,

    [string]$FilePath
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogPath = Join-Path $ScriptDir "organizer.log"
$HistoryPath = Join-Path $ScriptDir "organization-history.jsonl"
$BatchId = [guid]::NewGuid().ToString()

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

$ExtensionOwners = @{}
foreach ($Category in $Config.categories.PSObject.Properties) {
    foreach ($ConfiguredExtension in @($Category.Value)) {
        $NormalizedExtension = ([string]$ConfiguredExtension).ToLowerInvariant()
        if ($NormalizedExtension -notmatch '^\.[a-z0-9][a-z0-9._+-]*$') {
            Write-Host "Invalid extension under category '$($Category.Name)': '$ConfiguredExtension'" -ForegroundColor Red
            exit 1
        }
        if ($ExtensionOwners.ContainsKey($NormalizedExtension)) {
            Write-Host "Extension '$NormalizedExtension' is listed under both '$($ExtensionOwners[$NormalizedExtension])' and '$($Category.Name)' in config.json." -ForegroundColor Red
            exit 1
        }
        $ExtensionOwners[$NormalizedExtension] = $Category.Name
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
    param(
        [string]$Extension,
        [string]$FilePath
    )

    foreach ($Category in $Config.categories.PSObject.Properties) {

        if ($Category.Name -eq "Other") {
            continue
        }

        if ($Category.Value -contains $Extension) {
            return $Category.Name
        }
    }

    if ($Config.detectByContent -and $FilePath) {
        $DetectedCategory = Get-ContentCategory -Path $FilePath
        if ($DetectedCategory -and $Config.categories.PSObject.Properties[$DetectedCategory]) {
            return $DetectedCategory
        }
    }

    if ($Config.moveUnknownFiles) {
        return "Other"
    }

    return $null
}

function Get-ContentCategory {
    param([string]$Path)

    $Stream = $null
    try {
        $Stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $Bytes = New-Object byte[] 12
        $ReadCount = $Stream.Read($Bytes, 0, $Bytes.Length)
        if ($ReadCount -lt 4) { return $null }

        if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) { return "Images" }
        if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) { return "Images" }
        if ([System.Text.Encoding]::ASCII.GetString($Bytes, 0, 3) -eq "GIF") { return "Images" }
        if ([System.Text.Encoding]::ASCII.GetString($Bytes, 0, 5) -eq "%PDF-") { return "Documents" }
        if ($Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B -and $Bytes[2] -in @(0x03, 0x05, 0x07)) { return "Archives" }
        if ($Bytes[0] -eq 0x52 -and $Bytes[1] -eq 0x61 -and $Bytes[2] -eq 0x72 -and $Bytes[3] -eq 0x21 -and $Bytes[4] -eq 0x1A -and $Bytes[5] -eq 0x07) { return "Archives" }
        if ($Bytes[0] -eq 0x37 -and $Bytes[1] -eq 0x7A -and $Bytes[2] -eq 0xBC -and $Bytes[3] -eq 0xAF) { return "Archives" }
        if ([System.Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -eq "fLaC") { return "Music" }
        if ([System.Text.Encoding]::ASCII.GetString($Bytes, 0, 3) -eq "ID3") { return "Music" }
        if ([System.Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -eq "RIFF" -and [System.Text.Encoding]::ASCII.GetString($Bytes, 8, 4) -eq "WAVE") { return "Music" }
        if ($ReadCount -ge 8 -and [System.Text.Encoding]::ASCII.GetString($Bytes, 4, 4) -eq "ftyp") { return "Videos" }
        if ($Bytes[0] -eq 0x4D -and $Bytes[1] -eq 0x5A) { return "Installers" }
    }
    catch {
        return $null
    }
    finally {
        if ($Stream) { $Stream.Dispose() }
    }

    return $null
}

function Add-OrganizationHistory {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$CategoryName
    )

    $Record = [ordered]@{
        action = "move"
        moveId = [guid]::NewGuid().ToString()
        batchId = $BatchId
        timestamp = [DateTime]::UtcNow.ToString("o")
        sourcePath = $SourcePath
        destinationPath = $DestinationPath
        category = $CategoryName
    }

    Add-Content -LiteralPath $HistoryPath -Encoding UTF8 -Value ($Record | ConvertTo-Json -Compress)
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
    $Category = Get-Category -Extension $Extension -FilePath $File.FullName

    if (!$Category) {
        Write-Log "Skipped '$($File.Name)' - no matching category."
        return "Skipped"
    }

    $CategoryDirectory = Join-Path $Downloads $Category

    if (Test-Path -LiteralPath $CategoryDirectory) {
        $DestinationItem = Get-Item -LiteralPath $CategoryDirectory -Force

        if (
            !$DestinationItem.PSIsContainer -or
            ($DestinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        ) {
            Write-Log "Skipped '$($File.Name)' - destination is not a safe category folder."
            return "Failed"
        }
    }
    else {

        if ($DryRun) {
            Write-Host "[DRY RUN] Create folder: $CategoryDirectory"
        }
        else {
            try {
                [System.IO.Directory]::CreateDirectory($CategoryDirectory) | Out-Null
                Write-Log "Created folder: $Category"
            }
            catch {
                Write-Log "ERROR creating folder '$Category': $($_.Exception.Message)"
                return "Failed"
            }
        }
    }

    $DestinationDirectory = $CategoryDirectory
    if ($Config.sortByDate) {
        $YearDirectory = Join-Path $CategoryDirectory $File.LastWriteTime.ToString("yyyy")
        $DestinationDirectory = Join-Path $YearDirectory $File.LastWriteTime.ToString("MM")
        if ($DryRun) {
            Write-Host "[DRY RUN] Create date folders: $DestinationDirectory"
        }
        else {
            try {
                [System.IO.Directory]::CreateDirectory($YearDirectory) | Out-Null
                $YearItem = Get-Item -LiteralPath $YearDirectory -Force
                if (!$YearItem.PSIsContainer -or ($YearItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    Write-Log "Skipped '$($File.Name)' - unsafe year folder."
                    return "Failed"
                }
                [System.IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null
                $MonthItem = Get-Item -LiteralPath $DestinationDirectory -Force
                if (!$MonthItem.PSIsContainer -or ($MonthItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    Write-Log "Skipped '$($File.Name)' - unsafe month folder."
                    return "Failed"
                }
            }
            catch {
                Write-Log "ERROR creating date folder for '$($File.Name)': $($_.Exception.Message)"
                return "Failed"
            }
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
        try {
            Add-OrganizationHistory `
                -SourcePath $File.FullName `
                -DestinationPath $Destination `
                -CategoryName $Category
        }
        catch {
            Write-Log "ERROR recording history for '$($File.Name)': $($_.Exception.Message)"
        }
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

$Files = Get-ChildItem -LiteralPath $Downloads -File -ErrorAction Stop
$FailedMoveCount = 0

foreach ($File in $Files) {
    $MoveResult = Move-DownloadFile -File $File

    if ($MoveResult -eq "Failed") {
        $FailedMoveCount++
    }
}

if ($FailedMoveCount -gt 0) {
    Write-Log "Organizer finished with $FailedMoveCount failed move(s)."
    exit 2
}

Write-Log "Organizer finished."
