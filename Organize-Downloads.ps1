$Downloads = "$env:USERPROFILE\Downloads"

$Folders = @{
    "Images"     = @(".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg")
    "Videos"     = @(".mp4", ".mkv", ".mov", ".avi", ".webm")
    "Music"      = @(".mp3", ".wav", ".flac", ".m4a", ".aac")
    "Documents"  = @(".pdf", ".doc", ".docx", ".txt", ".ppt", ".pptx", ".xls", ".xlsx")
    "Archives"   = @(".zip", ".rar", ".7z", ".tar", ".gz")
    "Installers" = @(".exe", ".msi", ".msix", ".appx")
    "Code"       = @(
        ".py", ".js", ".ts", ".html", ".css",
        ".java", ".dart", ".cpp", ".c", ".cs",
        ".php", ".json", ".xml", ".sql"
    )
}

foreach ($Folder in $Folders.Keys) {

    $Destination = Join-Path $Downloads $Folder

    if (!(Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }
}

Get-ChildItem $Downloads -File | ForEach-Object {

    $File = $_
    $Extension = $File.Extension.ToLower()

    foreach ($Folder in $Folders.Keys) {

        if ($Folders[$Folder] -contains $Extension) {

            $Destination = Join-Path $Downloads $Folder
            $Target = Join-Path $Destination $File.Name

            # Avoid overwriting files with the same name
            if (Test-Path $Target) {

                $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
                $Extension = $File.Extension
                $Counter = 1

                do {
                    $NewName = "$BaseName ($Counter)$Extension"
                    $Target = Join-Path $Destination $NewName
                    $Counter++
                }
                while (Test-Path $Target)
            }

            Move-Item $File.FullName $Target

            Write-Host "Moved $($File.Name) -> $Folder"

            break
        }
    }
}

Write-Host ""
Write-Host "Downloads organized successfully!"