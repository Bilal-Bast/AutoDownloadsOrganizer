# AutoDownloadsOrganizer

A simple PowerShell script that automatically organizes your Windows Downloads folder by file type.

Instead of letting your Downloads folder become a mess, AutoDownloadsOrganizer sorts files into categories such as Images, Videos, Documents, Archives, Installers, Music, and Code.

## Features

- Automatically sorts files by extension
- Creates organization folders automatically
- Prevents files with duplicate names from being overwritten
- Works with the standard Windows Downloads folder
- No additional software required
- Easy to customize with your own file extensions
- Can be configured to run automatically when Windows starts

## Folder Structure

After running the script, your Downloads folder may look like:

```text
Downloads
├── Images
├── Videos
├── Music
├── Documents
├── Archives
├── Installers
└── Code
```

## Supported File Types

### Images

`.jpg` `.jpeg` `.png` `.gif` `.webp` `.bmp` `.svg`

### Videos

`.mp4` `.mkv` `.mov` `.avi` `.webm`

### Music

`.mp3` `.wav` `.flac` `.m4a` `.aac`

### Documents

`.pdf` `.doc` `.docx` `.txt` `.ppt` `.pptx` `.xls` `.xlsx`

### Archives

`.zip` `.rar` `.7z` `.tar` `.gz`

### Installers

`.exe` `.msi` `.msix` `.appx`

### Code

`.py` `.js` `.ts` `.html` `.css` `.java` `.dart` `.cpp` `.c` `.cs` `.php` `.json` `.xml` `.sql`

## Installation

### 1. Download the project

Clone the repository:

```powershell
git clone https://github.com/Bilal-Bast/AutoDownloadsOrganizer.git
```

Or download the repository as a ZIP from GitHub.

### 2. Run the script

Open PowerShell inside the project folder and run:

```powershell
.\Organize-Downloads.ps1
```

If PowerShell blocks local scripts, you can allow locally created scripts with:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Run Automatically at Startup

Press:

```text
Win + R
```

Enter:

```text
shell:startup
```

Create a shortcut with a target similar to:

```text
powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\AutoDownloadsOrganizer\Organize-Downloads.ps1"
```

The Downloads folder will then be organized whenever you sign in to Windows.

## Customization

You can add more extensions by editing the `$Folders` section inside `Organize-Downloads.ps1`.

Example:

```powershell
"Games" = @(".iso", ".rom")
```

## Safety

The script does not delete files.

Files are only moved into category folders inside the Downloads directory.

If another file already exists with the same name, the script automatically creates a new name such as:

```text
example (1).pdf
example (2).pdf
```

instead of overwriting the original file.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer

## Contributing

Pull requests and suggestions are welcome.

If you have ideas for new file categories or improvements, feel free to open an issue.

## License

This project is licensed under the MIT License.