# 📂 AutoDownloadsOrganizer

A lightweight PowerShell utility that automatically organizes your Windows **Downloads** folder by file type.

Instead of letting Downloads turn into a mess, AutoDownloadsOrganizer sorts files into clean categories such as **Images, Videos, Documents, Archives, Installers, Code, Android files, Rainmeter skins, Minecraft files, and more**.

V4 adds faster real-time monitoring, single-instance protection, duplicate event protection, and per-file processing.

---

## 🎬 Demo

See what AutoDownloadsOrganizer will do before moving anything:

![AutoDownloadsOrganizer Dry Run Demo](assets/dryrun-demo.png)

Use `-DryRun` to preview all file movements safely:

```powershell
.\Organize-Downloads.ps1 -DryRun
```

---

## ✨ Features

- 📁 Automatically sorts files by extension
- 👀 Real-time Downloads folder monitoring
- 🎯 Processes only the newly detected file in real-time mode
- 🔒 Prevents multiple watcher instances from running at the same time
- 🧯 Filters duplicate filesystem events
- ⏳ Waits until downloads are finished before moving them
- ⚙️ Fully configurable using `config.json`
- 🧪 Safe `-DryRun` mode before moving anything
- 🔄 Prevents duplicate files from being overwritten
- 📝 Creates an activity log
- 🚀 Optional automatic startup when you sign in to Windows
- 🗑️ Easy startup removal with `Uninstall.ps1`
- 📦 Supports many common file types
- ❓ Unknown files can automatically go into an `Other` folder
- 💻 No third-party software required
- 🔒 Does not require administrator privileges for normal use

---

## 📁 Project Structure

```text
AutoDownloadsOrganizer/
├── assets/
│   └── dryrun-demo.png
├── Organize-Downloads.ps1
├── Watch-Downloads.ps1
├── Install.ps1
├── Uninstall.ps1
├── config.json
├── README.md
├── LICENSE
└── .gitignore
```

---

## 🗂️ Default Categories

AutoDownloadsOrganizer can sort files into categories such as:

| Category | Examples |
|---|---|
| 🖼️ Images | `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`, `.svg` |
| 🎬 Videos | `.mp4`, `.mkv`, `.mov`, `.avi`, `.webm` |
| 🎵 Music | `.mp3`, `.wav`, `.flac`, `.m4a`, `.ogg` |
| 📄 Documents | `.pdf`, `.docx`, `.pptx`, `.xlsx`, `.txt`, `.csv` |
| 📦 Archives | `.zip`, `.rar`, `.7z`, `.tar`, `.gz` |
| 💿 Installers | `.exe`, `.msi`, `.msix`, `.appx`, `.appxbundle` |
| 🤖 Android | `.apk`, `.aab`, `.xapk`, `.apks` |
| 💽 Disk Images | `.iso`, `.img`, `.vhd`, `.vhdx` |
| 🔤 Fonts | `.ttf`, `.otf`, `.woff`, `.woff2` |
| 💻 Code | `.py`, `.js`, `.dart`, `.java`, `.cpp`, `.ps1`, `.gd`, and more |
| 🌧️ Rainmeter | `.rmskin` |
| ☕ Java & Minecraft | `.jar`, `.mcpack`, `.mcworld`, `.mcaddon` |
| 🎮 Game Files | Additional supported game-related formats |
| 📂 Other | Anything that does not match another category |

You can add, remove, or rename categories in `config.json`.

---

# 🚀 Installation

## Option 1 — Clone with Git

Open PowerShell and run:

```powershell
git clone https://github.com/Bilal-Bast/AutoDownloadsOrganizer.git
cd AutoDownloadsOrganizer
```

## Option 2 — Download ZIP

1. Click the green **Code** button on GitHub.
2. Select **Download ZIP**.
3. Extract the ZIP.
4. Open PowerShell inside the extracted folder.

---

# 🧪 Test Before Moving Files

It is recommended to run the organizer in **Dry Run mode** first:

```powershell
.\Organize-Downloads.ps1 -DryRun
```

Dry Run shows what the organizer **would** do without moving your files.

Example:

```text
[DRY RUN] wallpaper.png -> Images
[DRY RUN] setup.exe -> Installers
[DRY RUN] app-release.apk -> Android
[DRY RUN] fabric-api.jar -> Java & Minecraft
[DRY RUN] theme.rmskin -> Rainmeter
```

> Dry Run does not move your files, although normal logging may still occur.

---

# ▶️ Run the Organizer Once

When you're happy with the Dry Run results:

```powershell
.\Organize-Downloads.ps1
```

Your current Downloads folder will be organized immediately.

For example:

```text
Downloads/
├── Images/
├── Videos/
├── Music/
├── Documents/
├── Archives/
├── Installers/
├── Android/
├── Disk Images/
├── Fonts/
├── Code/
├── Rainmeter/
├── Java & Minecraft/
├── Game Files/
└── Other/
```

---

# 👀 Real-Time Monitoring

AutoDownloadsOrganizer V4 can continuously watch your Downloads folder and automatically organize new files as they arrive.

Start the real-time watcher with:

```powershell
.\Watch-Downloads.ps1
```

You should see:

```text
AutoDownloadsOrganizer V4
Watching: C:\Users\YourName\Downloads
Single-instance protection: Enabled
Press Ctrl+C to stop.
```

When a new file appears, AutoDownloadsOrganizer:

1. Detects the new file
2. Ignores temporary download files
3. Filters duplicate filesystem events
4. Waits until the file is finished downloading
5. Sends only that file to the organizer
6. Moves it into the correct category
7. Continues watching for more downloads

Example:

```text
Detected: wallpaper.png
Waiting for download to finish...
Organizing...
Moved 'wallpaper.png' -> 'Images'
Done.
```

Press:

```text
Ctrl + C
```

to stop the watcher.

---

## ⚡ Optimized Per-File Processing

Earlier versions could re-scan the entire Downloads folder whenever a new file appeared.

V4 uses a more efficient approach.

Instead of:

```text
New file
   ↓
Scan entire Downloads folder
   ↓
Organize everything
```

V4 does:

```text
New file
   ↓
Wait until ready
   ↓
Process only that file
   ↓
Move it
   ↓
Continue watching
```

The watcher uses:

```powershell
.\Organize-Downloads.ps1 -FilePath "C:\Users\YourName\Downloads\example.png"
```

internally to organize one file at a time.

This makes real-time mode faster and more efficient.

---

## 🔒 Single-Instance Protection

V4 prevents multiple watcher instances from running at the same time.

If `Watch-Downloads.ps1` is already running and you try to start it again:

```text
AutoDownloadsOrganizer is already running.
```

The second watcher exits automatically.

This helps prevent duplicate file processing and unnecessary background processes.

---

## 🧯 Duplicate Event Protection

Windows `FileSystemWatcher` can sometimes report the same file event more than once.

V4 tracks recently detected file paths and ignores duplicate events within a short time window.

This prevents the same download from being processed twice.

---

## ⏳ Temporary Download Protection

Browsers often create temporary files while a download is still in progress.

AutoDownloadsOrganizer ignores temporary extensions such as:

```text
.crdownload
.part
.partial
.tmp
.download
```

The watcher waits for the completed file before organizing it.

This helps prevent partially downloaded or locked files from being moved too early.

---

# ⚙️ Configuration

All settings and categories are stored inside:

```text
config.json
```

The default Downloads location is:

```json
"downloadsPath": "%USERPROFILE%\\Downloads"
```

You can change it to another folder if you want.

For example:

```json
"downloadsPath": "D:\\Downloads"
```

---

## 👀 Watcher Configuration

V4 also includes configurable watcher timing settings.

Example:

```json
"watcher": {
  "checkIntervalMilliseconds": 1000,
  "postReadyDelayMilliseconds": 500
}
```

### `checkIntervalMilliseconds`

Controls how long the watcher waits before checking again when a file is still locked.

Default:

```text
1000 ms
```

which is:

```text
1 second
```

### `postReadyDelayMilliseconds`

Adds a small extra delay after the file becomes available.

Default:

```text
500 ms
```

This helps avoid moving a file while a browser or application is performing final write or rename operations.

---

## Add Your Own Category

You can create custom categories by editing the `categories` section.

Example:

```json
"3D Models": [
  ".blend",
  ".fbx",
  ".obj",
  ".stl"
]
```

The organizer will automatically create:

```text
Downloads\3D Models
```

and move matching files there.

---

## Unknown Files

By default:

```json
"moveUnknownFiles": true
```

This means files that do not match any configured extension will be moved into:

```text
Other
```

If you would rather leave unknown files untouched, change it to:

```json
"moveUnknownFiles": false
```

---

# 🚀 Run Automatically When Windows Starts

AutoDownloadsOrganizer includes an installer script.

Run:

```powershell
.\Install.ps1
```

This creates a Windows Startup shortcut that launches:

```text
Watch-Downloads.ps1
```

automatically whenever you sign in to Windows.

The watcher then runs quietly in the background and organizes new downloads automatically.

Your project files are not copied or deleted.

---

# 🗑️ Disable Automatic Startup

Run:

```powershell
.\Uninstall.ps1
```

This removes the AutoDownloadsOrganizer startup shortcut.

It does **not** delete:

- Your Downloads
- Organized files
- The AutoDownloadsOrganizer project
- Your configuration

---

# 📝 Logging

The organizer records activity in:

```text
organizer.log
```

Example:

```text
[2026-10-05 12:14:01] Organizer started. DryRun=False
[2026-10-05 12:14:01] Moved 'wallpaper.png' -> 'Images'
[2026-10-05 12:14:01] Organizer finished.
```

Watcher messages are also logged.

Example:

```text
[2026-10-05 12:14:00] [Watcher] V4 watcher started.
```

Logging can help you see what the script moved and troubleshoot problems.

---

# 🔒 Duplicate File Protection

AutoDownloadsOrganizer will **not overwrite an existing file**.

If this file already exists:

```text
wallpaper.png
```

another file with the same name will automatically become:

```text
wallpaper (1).png
```

Then:

```text
wallpaper (2).png
```

and so on.

---

# 🛡️ Safety

AutoDownloadsOrganizer is designed to be simple and safe.

It:

- Does not delete your downloaded files
- Does not overwrite duplicate files
- Supports testing with `-DryRun`
- Waits for files to finish downloading
- Ignores common temporary download files
- Prevents multiple watcher instances
- Filters duplicate filesystem events
- Only organizes files in the configured directory
- Does not require administrator privileges for normal use

Always check the Dry Run output before using a new configuration.

---

# 🖥️ Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1+ or compatible PowerShell
- Git is optional and only needed if cloning the repository

---

# ⚠️ PowerShell Execution Policy

If Windows prevents the scripts from running, you can allow locally created PowerShell scripts for your account:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

You can check your current execution policies with:

```powershell
Get-ExecutionPolicy -List
```

---

# 🧰 Scripts

## `Organize-Downloads.ps1`

Organizes the Downloads folder once.

```powershell
.\Organize-Downloads.ps1
```

Preview changes safely with:

```powershell
.\Organize-Downloads.ps1 -DryRun
```

It also supports single-file processing:

```powershell
.\Organize-Downloads.ps1 -FilePath "C:\Users\YourName\Downloads\example.png"
```

This mode is primarily used internally by the V4 watcher.

---

## `Watch-Downloads.ps1`

Continuously watches the Downloads folder and automatically organizes new files.

```powershell
.\Watch-Downloads.ps1
```

V4 includes:

- Single-instance protection
- Duplicate event protection
- File-ready checking
- Per-file processing
- Temporary download filtering

---

## `Install.ps1`

Adds AutoDownloadsOrganizer to Windows Startup.

```powershell
.\Install.ps1
```

---

## `Uninstall.ps1`

Removes the Windows Startup shortcut.

```powershell
.\Uninstall.ps1
```

---

# 🧪 Testing V4

## Test Single-Instance Protection

Start the watcher:

```powershell
.\Watch-Downloads.ps1
```

Then open another PowerShell window and run it again:

```powershell
.\Watch-Downloads.ps1
```

Expected output:

```text
AutoDownloadsOrganizer is already running.
```

---

## Test Real-Time Organization

With the watcher running, create a test file:

```powershell
New-Item "$env:USERPROFILE\Downloads\v4-test.png" -ItemType File
```

The watcher should detect and move it automatically.

Verify:

```powershell
Test-Path "$env:USERPROFILE\Downloads\Images\v4-test.png"
```

Expected:

```text
True
```

---

## Test Manual Organization

Create another test file:

```powershell
New-Item "$env:USERPROFILE\Downloads\manual-test.pdf" -ItemType File
```

Preview:

```powershell
.\Organize-Downloads.ps1 -DryRun
```

Then organize:

```powershell
.\Organize-Downloads.ps1
```

---

# 📌 Version History

## V4

- 🔒 Added single-instance watcher protection
- 🎯 Added per-file real-time processing
- 🧯 Added duplicate filesystem event protection
- ⚡ Improved real-time performance
- ⚙️ Added configurable watcher timing
- 📝 Improved watcher logging

## V3

- 👀 Added real-time Downloads monitoring
- ⏳ Added file-ready detection
- 🧩 Added browser temporary file handling

## V2

- ⚙️ Added `config.json`
- 🧪 Added `-DryRun`
- 📝 Added logging
- 🚀 Added startup installer
- 🗑️ Added startup uninstaller
- 📦 Added more file categories

## V1

- 📁 Initial file organization by extension
- 🔄 Duplicate filename protection

---

# 🤝 Contributing

Contributions are welcome!

You can:

- Add support for more file types
- Suggest new categories
- Improve PowerShell code
- Improve documentation
- Report bugs
- Suggest new features

Feel free to open an **Issue** or submit a **Pull Request**.

---

# 🗺️ Planned Features

Possible future improvements include:

- 🖥️ GUI configuration tool
- 📋 System tray controls
- 🔔 Optional Windows notifications
- ↩️ Undo last organization
- 📊 Organization statistics
- 📅 Sort files by date
- 🧠 Smarter file detection
- 📦 Easy installer/release package

---

# 📜 License

This project is licensed under the **MIT License**.

See the `LICENSE` file for details.

---

## ⭐ Like the Project?

If AutoDownloadsOrganizer is useful to you, consider giving the repository a ⭐ on GitHub!

Made with PowerShell for a cleaner Windows Downloads folder. 🧹