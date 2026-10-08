param(
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$OutputDirectory = Join-Path $ProjectRoot "release"
$Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot "VERSION") -Raw).Trim()
$ExecutableVersion = if ($Version -match '^\d+\.\d+\.\d+$') { "$Version.0" } else { $Version }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$PackageName = "AutoDownloadsOrganizer-$Version"
$PackageDirectory = Join-Path $OutputDirectory $PackageName
$ExePath = Join-Path $PackageDirectory "AutoDownloadsOrganizer.exe"

if (!(Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
    throw "PS2EXE is required. Install it with: Install-Module ps2exe -Scope CurrentUser"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if (Test-Path -LiteralPath $PackageDirectory) {
    $ResolvedOutput = [System.IO.Path]::GetFullPath($PackageDirectory)
    if (!$ResolvedOutput.StartsWith($OutputDirectory + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean a package path outside the output directory."
    }
    Remove-Item -LiteralPath $ResolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $PackageDirectory -Force | Out-Null

$IconPath = Join-Path $ProjectRoot "assets\AutoDownloadsOrganizer.ico"
Invoke-PS2EXE `
    -inputFile (Join-Path $ProjectRoot "AutoDownloadsOrganizer.ps1") `
    -outputFile $ExePath `
    -noConsole `
    -DPIAware `
    -iconFile $IconPath `
    -title "AutoDownloadsOrganizer" `
    -description "Organizes files in the Windows Downloads folder" `
    -product "AutoDownloadsOrganizer" `
    -version $ExecutableVersion

$RequiredFiles = @(
    "Organize-Downloads.ps1",
    "Watch-Downloads.ps1",
    "Undo-Last-Organization.ps1",
    "Install.ps1",
    "Uninstall.ps1",
    "config.json",
    "VERSION",
    "README.md",
    "LICENSE"
)
foreach ($Name in $RequiredFiles) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $Name) -Destination $PackageDirectory
}
Copy-Item -LiteralPath (Join-Path $ProjectRoot "assets") -Destination $PackageDirectory -Recurse

$ZipPath = Join-Path $OutputDirectory "$PackageName-portable.zip"
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Compress-Archive -LiteralPath $PackageDirectory -DestinationPath $ZipPath
Write-Host "Portable package created: $ZipPath"

if (!$SkipInstaller) {
    $Compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($Compiler) {
        & $Compiler.Source (Join-Path $ProjectRoot "installer\AutoDownloadsOrganizer.iss")
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup exited with code $LASTEXITCODE." }
    }
    else {
        Write-Warning "Inno Setup was not found. The portable ZIP is ready; install Inno Setup and rerun to build the installer."
    }
}
