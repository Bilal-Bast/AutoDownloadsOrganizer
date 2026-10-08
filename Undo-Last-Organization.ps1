$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$HistoryPath = Join-Path $ScriptDir "organization-history.jsonl"
$LogPath = Join-Path $ScriptDir "organizer.log"

if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { exit 1 }
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$Downloads = if ($Config.downloadsPath) {
    [Environment]::ExpandEnvironmentVariables($Config.downloadsPath)
}
else {
    Join-Path $env:USERPROFILE "Downloads"
}
function Get-NormalizedPath {
    param([string]$Path)
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Root = [System.IO.Path]::GetPathRoot($FullPath)
    if ($FullPath.Length -gt $Root.Length) {
        $FullPath = $FullPath.TrimEnd([char[]]@('\', '/'))
    }
    return $FullPath
}

$Downloads = Get-NormalizedPath $Downloads

function Test-DescendantPath {
    param([string]$Path, [string]$Parent)
    $NormalizedPath = Get-NormalizedPath $Path
    $NormalizedParent = Get-NormalizedPath $Parent
    $Prefix = $NormalizedParent
    if (!$Prefix.EndsWith([string][System.IO.Path]::DirectorySeparatorChar)) {
        $Prefix += [System.IO.Path]::DirectorySeparatorChar
    }
    return $NormalizedPath.StartsWith(
        $Prefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-UniquePath {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return $Path }
    $Directory = [System.IO.Path]::GetDirectoryName($Path)
    $Name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $Extension = [System.IO.Path]::GetExtension($Path)
    $Index = 1
    do {
        $Candidate = Join-Path $Directory "$Name (undo $Index)$Extension"
        $Index++
    } while (Test-Path -LiteralPath $Candidate)
    return $Candidate
}

function Write-UndoLog {
    param([string]$Message)
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [Undo] $Message"
}

if (!(Test-Path -LiteralPath $HistoryPath -PathType Leaf)) {
    Write-Host "No organization history is available to undo."
    exit 3
}

$Records = @(
    Get-Content -LiteralPath $HistoryPath -Encoding UTF8 | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $_ }
)
$Moves = @($Records | Where-Object { $_.action -eq "move" })
$UndoneIds = @{}
foreach ($Record in $Records | Where-Object { $_.action -eq "undo" -and $_.undoOf }) {
    $UndoneIds[[string]$Record.undoOf] = $true
}

$SelectedBatch = $null
$BatchIds = @($Moves | Select-Object -ExpandProperty batchId -Unique)
for ($Index = $BatchIds.Count - 1; $Index -ge 0; $Index--) {
    $CandidateMoves = @($Moves | Where-Object { $_.batchId -eq $BatchIds[$Index] })
    if (@($CandidateMoves | Where-Object { !$UndoneIds.ContainsKey([string]$_.moveId) }).Count -gt 0) {
        $SelectedBatch = $BatchIds[$Index]
        break
    }
}

if (!$SelectedBatch) {
    Write-Host "There are no organized files left to undo."
    exit 3
}

$BatchMoves = @($Moves | Where-Object { $_.batchId -eq $SelectedBatch })
[array]::Reverse($BatchMoves)
$Succeeded = 0
$Failed = 0

foreach ($Move in $BatchMoves) {
    $MoveId = [string]$Move.moveId
    if ($UndoneIds.ContainsKey($MoveId)) { continue }

    try {
        $OriginalPath = Get-NormalizedPath ([string]$Move.sourcePath)
        $OrganizedPath = Get-NormalizedPath ([string]$Move.destinationPath)
        $OriginalParent = Get-NormalizedPath ([System.IO.Path]::GetDirectoryName($OriginalPath))
        $CategoryName = [string]$Move.category

        if (
            [string]::IsNullOrWhiteSpace($CategoryName) -or
            $CategoryName.Contains('\') -or
            $CategoryName.Contains('/') -or
            $CategoryName -in @('.', '..') -or
            $CategoryName -ne $CategoryName.Trim() -or
            $CategoryName.EndsWith('.') -or
            $CategoryName -match '[:*?"<>|]' -or
            $CategoryName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$' -or
            ![string]::Equals($OriginalParent, $Downloads, [System.StringComparison]::OrdinalIgnoreCase) -or
            !$CategoryName
        ) {
            throw "History entry failed path validation."
        }

        $CategoryDirectory = Get-NormalizedPath (Join-Path $Downloads $CategoryName)
        if (!(Test-DescendantPath $CategoryDirectory $Downloads) -or !(Test-DescendantPath $OrganizedPath $CategoryDirectory)) {
            throw "Recorded destination is outside its category folder."
        }
        if (!(Test-Path -LiteralPath $OrganizedPath -PathType Leaf)) {
            throw "Organized file is missing: $OrganizedPath"
        }

        $File = Get-Item -LiteralPath $OrganizedPath -Force
        if ($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to move a reparse-point file."
        }

        # Refuse reparse-point category/date directories that could redirect a move.
        $CurrentDirectory = [System.IO.Path]::GetDirectoryName($OrganizedPath)
        while (Test-DescendantPath $CurrentDirectory $Downloads) {
            $DirectoryItem = Get-Item -LiteralPath $CurrentDirectory -Force
            if ($DirectoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Refusing to move through a reparse-point directory."
            }
            if ([string]::Equals($CurrentDirectory, $CategoryDirectory, [System.StringComparison]::OrdinalIgnoreCase)) { break }
            $CurrentDirectory = [System.IO.Path]::GetDirectoryName($CurrentDirectory)
        }

        $RestorePath = Get-UniquePath $OriginalPath
        Move-Item -LiteralPath $OrganizedPath -Destination $RestorePath -ErrorAction Stop

        $UndoRecord = [ordered]@{
            action = "undo"
            moveId = [guid]::NewGuid().ToString()
            undoOf = $MoveId
            batchId = $SelectedBatch
            timestamp = [DateTime]::UtcNow.ToString("o")
            restoredPath = $RestorePath
            category = $CategoryName
        }
        Add-Content -LiteralPath $HistoryPath -Encoding UTF8 -Value ($UndoRecord | ConvertTo-Json -Compress)
        $UndoneIds[$MoveId] = $true
        $Succeeded++
        Write-UndoLog "Restored '$([System.IO.Path]::GetFileName($RestorePath))' from '$CategoryName'."
    }
    catch {
        $Failed++
        Write-UndoLog "ERROR undoing '$($Move.destinationPath)': $($_.Exception.Message)"
    }
}

Write-Host "Undo complete: $Succeeded restored; $Failed failed."
Write-UndoLog "Batch $SelectedBatch undo finished: $Succeeded restored; $Failed failed."
if ($Failed -gt 0) { exit 2 }
exit 0
