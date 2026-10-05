$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OrganizerScript = Join-Path $ScriptDir "Organize-Downloads.ps1"

if (!(Test-Path $OrganizerScript)) {
    Write-Host "Organize-Downloads.ps1 was not found." -ForegroundColor Red
    exit 1
}

$StartupFolder = [Environment]::GetFolderPath("Startup")

$ShortcutPath = Join-Path `
    $StartupFolder `
    "AutoDownloadsOrganizer.lnk"

$Shell = New-Object -ComObject WScript.Shell

$Shortcut = $Shell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath = "powershell.exe"

$Shortcut.Arguments = `
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$OrganizerScript`""

$Shortcut.WorkingDirectory = $ScriptDir

$Shortcut.Description = `
    "Automatically organize the Windows Downloads folder"

$Shortcut.Save()

Write-Host ""
Write-Host "AutoDownloadsOrganizer installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "The organizer will run automatically when you sign in to Windows."
Write-Host ""
Write-Host "Startup shortcut:"
Write-Host $ShortcutPath