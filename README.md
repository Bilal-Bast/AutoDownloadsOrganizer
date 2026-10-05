# 📂 AutoDownloadsOrganizer

A lightweight PowerShell utility that automatically organizes your Windows **Downloads** folder by file type.

Instead of letting Downloads turn into a mess, AutoDownloadsOrganizer sorts files into clean categories such as **Images, Videos, Documents, Archives, Installers, Code, Android files, Rainmeter skins, Minecraft files, and more**.

---

## ✨ Features

- 📁 Automatically sorts files by extension
- ⚙️ Fully configurable using `config.json`
- 🧪 Safe `-DryRun` mode before moving anything
- 🔄 Prevents duplicate files from being overwritten
- 📝 Creates an activity log
- 🚀 Optional automatic startup when you sign in to Windows
- 🗑️ Easy startup removal with `Uninstall.ps1`
- 📦 Supports many common file types
- ❓ Unknown files can automatically go into an `Other` folder
- 💻 No third-party software required

---

## 📁 Project Structure

```text
AutoDownloadsOrganizer/
├── Organize-Downloads.ps1
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
| 💿 Installers | `.exe`, `.msi`, `.msix`, `.appx` |
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

# ▶️ Run the Organizer

When you're happy with the Dry Run results:

```powershell
.\Organize-Downloads.ps1
```

Your Downloads folder will be organized automatically.

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

# ⚙️ Configuration

All categories are stored inside:

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

This creates a startup shortcut so the organizer automatically runs whenever you sign in to Windows.

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
[2026-10-05 11:41:37] Organizer started. DryRun=False
[2026-10-05 11:41:37] Moved 'wallpaper.png' -> 'Images'
[2026-10-05 11:41:37] Moved 'setup.exe' -> 'Installers'
[2026-10-05 11:41:37] Organizer finished.
```

This can help you see what the script moved and troubleshoot problems.

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

- 👀 Real-time Downloads folder monitoring
- ⏳ Wait until downloads finish before moving them
- 🖥️ GUI configuration tool
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