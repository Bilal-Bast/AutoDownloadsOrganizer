param(
    [switch]$DryRun
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogPath = Join-Path $ScriptDir "organizer.log"

if (!(Test-Path $ConfigPath)) {
    Write-Host "config.json was not found." -ForegroundColor Red
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

    if (!(Test-Path $Target)) {
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
    while (Test-Path $Target)

    return $Target
}

Write-Log "Organizer started. DryRun=$DryRun"

foreach ($Category in $Config.categories.PSObject.Properties) {

    $FolderName = $Category.Name

    $DestinationFolder = Join-Path $Downloads $FolderName

    if (!(Test-Path $DestinationFolder)) {

        if ($DryRun) {
            Write-Host "[DRY RUN] Create folder: $DestinationFolder"
        }
        else {
            New-Item -ItemType Directory -Path $DestinationFolder | Out-Null
            Write-Log "Created folder: $FolderName"
        }
    }
}

$Files = Get-ChildItem -Path $Downloads -File

foreach ($File in $Files) {

    $Extension = $File.Extension.ToLower()
    $MatchedCategory = $null

    foreach ($Category in $Config.categories.PSObject.Properties) {

        if ($Category.Value -contains $Extension) {
            $MatchedCategory = $Category.Name
            break
        }
    }

    if (!$MatchedCategory -and $Config.moveUnknownFiles) {
        $MatchedCategory = "Other"
    }

    if (!$MatchedCategory) {
        continue
    }

    $DestinationDirectory = Join-Path $Downloads $MatchedCategory

    if (!(Test-Path $DestinationDirectory) -and !$DryRun) {
        New-Item -ItemType Directory -Path $DestinationDirectory | Out-Null
    }

    $Destination = Get-UniqueDestination `
        -Directory $DestinationDirectory `
        -FileName $File.Name

    if ($DryRun) {

        Write-Host "[DRY RUN] $($File.Name) -> $MatchedCategory"

    }
    else {

        try {

            Move-Item `
                -LiteralPath $File.FullName `
                -Destination $Destination `
                -ErrorAction Stop

            Write-Log "Moved '$($File.Name)' -> '$MatchedCategory'"

        }
        catch {

            Write-Log "ERROR moving '$($File.Name)': $($_.Exception.Message)"

        }
    }
}

Write-Log "Organizer finished."