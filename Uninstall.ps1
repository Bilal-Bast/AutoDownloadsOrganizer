$StartupFolder = [Environment]::GetFolderPath("Startup")

$ShortcutPath = Join-Path `
    $StartupFolder `
    "AutoDownloadsOrganizer.lnk"

if (Test-Path $ShortcutPath) {

    Remove-Item $ShortcutPath -Force

    Write-Host ""
    Write-Host "AutoDownloadsOrganizer startup task removed." `
        -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "AutoDownloadsOrganizer is not installed for startup."

}

Write-Host ""
Write-Host "Your files and project folder were not deleted."