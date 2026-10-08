Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------
# AutoDownloadsOrganizer V5
# GUI + System Tray Control Center
# ---------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$OrganizerPath = Join-Path $ScriptDir "Organize-Downloads.ps1"
$WatcherPath   = Join-Path $ScriptDir "Watch-Downloads.ps1"
$InstallPath   = Join-Path $ScriptDir "Install.ps1"
$UninstallPath = Join-Path $ScriptDir "Uninstall.ps1"
$ConfigPath    = Join-Path $ScriptDir "config.json"
$LogPath       = Join-Path $ScriptDir "organizer.log"

# ---------------------------------------------------------
# Configuration helpers
# ---------------------------------------------------------

function Get-AppConfig {

    if (!(Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $ConfigPath -Raw |
            ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-DownloadsPath {

    $Config = Get-AppConfig

    if ($Config -and $Config.downloadsPath) {

        return [Environment]::ExpandEnvironmentVariables(
            $Config.downloadsPath
        )
    }

    return Join-Path $env:USERPROFILE "Downloads"
}

# ---------------------------------------------------------
# Watcher process detection
# ---------------------------------------------------------

function Get-WatcherProcesses {

    $Processes = Get-CimInstance Win32_Process `
        -ErrorAction SilentlyContinue |
        Where-Object {
            (
                $_.Name -eq "powershell.exe" -or
                $_.Name -eq "pwsh.exe"
            ) -and
            $_.CommandLine -and
            $_.CommandLine.IndexOf(
                $WatcherPath,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        }

    return @($Processes)
}

function Test-WatcherRunning {

    $Processes = @(Get-WatcherProcesses)

    return ($Processes.Count -gt 0)
}

# ---------------------------------------------------------
# Message helper
# ---------------------------------------------------------

function Show-AppMessage {

    param(
        [string]$Message,
        [string]$Title = "AutoDownloadsOrganizer",
        [System.Windows.Forms.MessageBoxIcon]$Icon =
            [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    ) | Out-Null
}

# ---------------------------------------------------------
# Main form
# ---------------------------------------------------------

$Form = New-Object System.Windows.Forms.Form

$Form.Text = "AutoDownloadsOrganizer V5"
$Form.Size = New-Object System.Drawing.Size(570, 620)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedSingle"
$Form.MaximizeBox = $false

$Form.BackColor =
    [System.Drawing.Color]::FromArgb(25, 25, 28)

$Form.ForeColor =
    [System.Drawing.Color]::White

$Form.Font =
    New-Object System.Drawing.Font("Segoe UI", 9)

$Form.Icon = [System.Drawing.SystemIcons]::Application

# Used to distinguish real exit from hide-to-tray.
$Form.Tag = ""

# ---------------------------------------------------------
# Title
# ---------------------------------------------------------

$TitleLabel = New-Object System.Windows.Forms.Label

$TitleLabel.Text = "AutoDownloadsOrganizer"

$TitleLabel.Font =
    New-Object System.Drawing.Font(
        "Segoe UI",
        20,
        [System.Drawing.FontStyle]::Bold
    )

$TitleLabel.AutoSize = $true

$TitleLabel.Location =
    New-Object System.Drawing.Point(28, 24)

$Form.Controls.Add($TitleLabel)

# ---------------------------------------------------------
# Subtitle
# ---------------------------------------------------------

$SubtitleLabel = New-Object System.Windows.Forms.Label

$SubtitleLabel.Text =
    "Keep your Downloads folder clean automatically."

$SubtitleLabel.Font =
    New-Object System.Drawing.Font("Segoe UI", 10)

$SubtitleLabel.ForeColor =
    [System.Drawing.Color]::FromArgb(175, 175, 180)

$SubtitleLabel.AutoSize = $true

$SubtitleLabel.Location =
    New-Object System.Drawing.Point(31, 68)

$Form.Controls.Add($SubtitleLabel)

# ---------------------------------------------------------
# Monitoring status
# ---------------------------------------------------------

$StatusLabel = New-Object System.Windows.Forms.Label

$StatusLabel.Font =
    New-Object System.Drawing.Font(
        "Segoe UI",
        11,
        [System.Drawing.FontStyle]::Bold
    )

$StatusLabel.AutoSize = $true

$StatusLabel.Location =
    New-Object System.Drawing.Point(32, 110)

$Form.Controls.Add($StatusLabel)

# ---------------------------------------------------------
# Button creator
# ---------------------------------------------------------

function New-AppButton {

    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 235,
        [int]$Height = 45
    )

    $Button = New-Object System.Windows.Forms.Button

    $Button.Text = $Text

    $Button.Location =
        New-Object System.Drawing.Point($X, $Y)

    $Button.Size =
        New-Object System.Drawing.Size($Width, $Height)

    $Button.FlatStyle =
        [System.Windows.Forms.FlatStyle]::Flat

    $Button.FlatAppearance.BorderSize = 1

    $Button.FlatAppearance.BorderColor =
        [System.Drawing.Color]::FromArgb(70, 70, 75)

    $Button.BackColor =
        [System.Drawing.Color]::FromArgb(40, 40, 44)

    $Button.ForeColor =
        [System.Drawing.Color]::White

    $Button.Font =
        New-Object System.Drawing.Font("Segoe UI", 10)

    $Button.Cursor =
        [System.Windows.Forms.Cursors]::Hand

    $Button.TabStop = $false

    $Form.Controls.Add($Button)

    return $Button
}

# ---------------------------------------------------------
# Buttons
# ---------------------------------------------------------

$OrganizeButton = New-AppButton `
    -Text "Organize Now" `
    -X 30 `
    -Y 155

$DryRunButton = New-AppButton `
    -Text "Dry Run" `
    -X 285 `
    -Y 155

$StartWatcherButton = New-AppButton `
    -Text "Start Monitoring" `
    -X 30 `
    -Y 215

$StopWatcherButton = New-AppButton `
    -Text "Stop Monitoring" `
    -X 285 `
    -Y 215

$DownloadsButton = New-AppButton `
    -Text "Open Downloads" `
    -X 30 `
    -Y 290

$ConfigButton = New-AppButton `
    -Text "Edit Configuration" `
    -X 285 `
    -Y 290

$LogButton = New-AppButton `
    -Text "Open Activity Log" `
    -X 30 `
    -Y 350

$ProjectButton = New-AppButton `
    -Text "Open Project Folder" `
    -X 285 `
    -Y 350

$InstallButton = New-AppButton `
    -Text "Enable Windows Startup" `
    -X 30 `
    -Y 425

$UninstallButton = New-AppButton `
    -Text "Disable Windows Startup" `
    -X 285 `
    -Y 425

# ---------------------------------------------------------
# Footer
# ---------------------------------------------------------

$Footer = New-Object System.Windows.Forms.Label

$Footer.Text = "V5 | PowerShell | Windows 10 / 11"

$Footer.AutoSize = $true

$Footer.ForeColor =
    [System.Drawing.Color]::FromArgb(130, 130, 135)

$Footer.Font =
    New-Object System.Drawing.Font("Segoe UI", 9)

$Footer.Location =
    New-Object System.Drawing.Point(30, 520)

$Form.Controls.Add($Footer)

# ---------------------------------------------------------
# Tray icon
# ---------------------------------------------------------

$TrayIcon = New-Object System.Windows.Forms.NotifyIcon

$TrayIcon.Icon =
    [System.Drawing.SystemIcons]::Application

$TrayIcon.Visible = $true

$TrayIcon.Text =
    "AutoDownloadsOrganizer"

# ---------------------------------------------------------
# Tray notification helper
# ---------------------------------------------------------

function Show-TrayNotification {

    param(
        [string]$Title,
        [string]$Message
    )

    try {

        $TrayIcon.BalloonTipTitle = $Title
        $TrayIcon.BalloonTipText = $Message

        $TrayIcon.BalloonTipIcon =
            [System.Windows.Forms.ToolTipIcon]::Info

        $TrayIcon.ShowBalloonTip(2500)

    }
    catch {
        # Ignore notification failures.
    }
}

# ---------------------------------------------------------
# Status updater
# ---------------------------------------------------------

function Update-WatcherStatus {

    $Running = Test-WatcherRunning

    if ($Running) {

        $StatusLabel.Text =
            "Real-time monitoring: ON"

        $StatusLabel.ForeColor =
            [System.Drawing.Color]::FromArgb(
                70,
                200,
                100
            )

        $StartWatcherButton.Enabled = $false
        $StopWatcherButton.Enabled = $true

        if ($StartMenuItem) {
            $StartMenuItem.Enabled = $false
        }

        if ($StopMenuItem) {
            $StopMenuItem.Enabled = $true
        }

        $TrayIcon.Text =
            "AutoDownloadsOrganizer - Monitoring"
    }
    else {

        $StatusLabel.Text =
            "Real-time monitoring: OFF"

        $StatusLabel.ForeColor =
            [System.Drawing.Color]::FromArgb(
                220,
                70,
                70
            )

        $StartWatcherButton.Enabled = $true
        $StopWatcherButton.Enabled = $false

        if ($StartMenuItem) {
            $StartMenuItem.Enabled = $true
        }

        if ($StopMenuItem) {
            $StopMenuItem.Enabled = $false
        }

        $TrayIcon.Text =
            "AutoDownloadsOrganizer - Stopped"
    }
}

# ---------------------------------------------------------
# Start watcher helper
# ---------------------------------------------------------

function Start-DownloadsWatcher {

    if (Test-WatcherRunning) {

        Update-WatcherStatus

        Show-AppMessage `
            "Real-time monitoring is already running."

        return
    }

    if (!(Test-Path -LiteralPath $WatcherPath)) {

        Show-AppMessage `
            "Watch-Downloads.ps1 could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)

        return
    }

    try {

        $Arguments =
            "-NoProfile -ExecutionPolicy Bypass -File `"$WatcherPath`""

        Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $Arguments `
            -WindowStyle Hidden

        Start-Sleep -Milliseconds 800

        Update-WatcherStatus

        if (Test-WatcherRunning) {

            Show-TrayNotification `
                "Monitoring Started" `
                "Your Downloads folder is now being monitored."
        }
        else {

            Show-AppMessage `
                "The watcher did not start successfully. Check organizer.log for details." `
                "Watcher Error" `
                ([System.Windows.Forms.MessageBoxIcon]::Error)
        }

    }
    catch {

        Show-AppMessage `
            $_.Exception.Message `
            "Watcher Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# ---------------------------------------------------------
# Stop watcher helper
# ---------------------------------------------------------

function Stop-DownloadsWatcher {

    $Processes = @(Get-WatcherProcesses)

    if ($Processes.Count -eq 0) {

        Update-WatcherStatus
        return
    }

    foreach ($Process in $Processes) {

        try {

            Stop-Process `
                -Id $Process.ProcessId `
                -Force `
                -ErrorAction SilentlyContinue

        }
        catch {
        }
    }

    Start-Sleep -Milliseconds 500

    Update-WatcherStatus

    Show-TrayNotification `
        "Monitoring Stopped" `
        "Real-time monitoring has been stopped."
}

# ---------------------------------------------------------
# Organize Now button
# ---------------------------------------------------------

$script:OrganizerProcess = $null
$script:ShowOrganizationCompletionDialog = $false
$OrganizerPollTimer = New-Object System.Windows.Forms.Timer
$OrganizerPollTimer.Interval = 500

function Start-DownloadsOrganization {
    param([switch]$ShowCompletionDialog)

    if ($script:OrganizerProcess) {
        try {
            $script:OrganizerProcess.Refresh()

            if (!$script:OrganizerProcess.HasExited) {
                Show-AppMessage "Organization is already in progress."
                return
            }

            $script:OrganizerProcess.Dispose()
            $script:OrganizerProcess = $null
        }
        catch {
            $script:OrganizerProcess = $null
        }
    }

    if (!(Test-Path -LiteralPath $OrganizerPath -PathType Leaf)) {
        Show-AppMessage `
            "Organize-Downloads.ps1 could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)

        return
    }

    try {
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$OrganizerPath`""

        $script:OrganizerProcess = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $Arguments `
            -WindowStyle Hidden `
            -PassThru

        $script:ShowOrganizationCompletionDialog = [bool]$ShowCompletionDialog
        $OrganizeButton.Enabled = $false
        $OrganizeButton.Text = "Organizing..."

        if ($OrganizeMenuItem) {
            $OrganizeMenuItem.Enabled = $false
        }

        $OrganizerPollTimer.Start()
    }
    catch {
        Show-AppMessage `
            $_.Exception.Message `
            "Organizer Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)

        $OrganizeButton.Enabled = $true
        $OrganizeButton.Text = "Organize Now"

        if ($OrganizeMenuItem) {
            $OrganizeMenuItem.Enabled = $true
        }
    }
}

$OrganizerPollTimer.Add_Tick({
    if (!$script:OrganizerProcess) {
        $OrganizerPollTimer.Stop()
        return
    }

    try {
        $script:OrganizerProcess.Refresh()

        if (!$script:OrganizerProcess.HasExited) {
            return
        }

        $ExitCode = $script:OrganizerProcess.ExitCode
        $script:OrganizerProcess.Dispose()
        $script:OrganizerProcess = $null

        $OrganizeButton.Enabled = $true
        $OrganizeButton.Text = "Organize Now"

        if ($OrganizeMenuItem) {
            $OrganizeMenuItem.Enabled = $true
        }

        if ($ExitCode -eq 0) {
            Show-TrayNotification `
                "Organization Complete" `
                "Your Downloads folder has been organized."

            if ($script:ShowOrganizationCompletionDialog) {
                Show-AppMessage "Downloads organization completed successfully."
            }
        }
        else {
            try {
                Add-Content `
                    -LiteralPath $LogPath `
                    -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [GUI] Organizer exited with code $ExitCode."
            }
            catch {
            }

            Show-TrayNotification `
                "Organization Needs Attention" `
                "Some files could not be organized. Check organizer.log."

            if ($script:ShowOrganizationCompletionDialog) {
                $ErrorMessage = if ($ExitCode -eq 2) {
                    "Some files could not be moved. Check organizer.log for details."
                }
                else {
                    "The organizer exited with code $ExitCode. Check config.json and organizer.log."
                }

                Show-AppMessage `
                    $ErrorMessage `
                    "Organization Error" `
                    ([System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    }
    catch {
        $OrganizerPollTimer.Stop()
        $script:OrganizerProcess = $null
        $OrganizeButton.Enabled = $true
        $OrganizeButton.Text = "Organize Now"

        if ($OrganizeMenuItem) {
            $OrganizeMenuItem.Enabled = $true
        }

        Show-AppMessage `
            $_.Exception.Message `
            "Organizer Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$OrganizeButton.Add_Click({
    Start-DownloadsOrganization -ShowCompletionDialog
})

# ---------------------------------------------------------
# Dry Run button
# ---------------------------------------------------------

$DryRunButton.Add_Click({

    if (!(Test-Path -LiteralPath $OrganizerPath)) {

        Show-AppMessage `
            "Organize-Downloads.ps1 could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)

        return
    }

    try {

        $Arguments =
            "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$OrganizerPath`" -DryRun"

        Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $Arguments

    }
    catch {

        Show-AppMessage `
            $_.Exception.Message `
            "Dry Run Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ---------------------------------------------------------
# Start monitoring button
# ---------------------------------------------------------

$StartWatcherButton.Add_Click({

    Start-DownloadsWatcher
})

# ---------------------------------------------------------
# Stop monitoring button
# ---------------------------------------------------------

$StopWatcherButton.Add_Click({

    Stop-DownloadsWatcher
})

# ---------------------------------------------------------
# Open Downloads button
# ---------------------------------------------------------

$DownloadsButton.Add_Click({

    $Downloads = Get-DownloadsPath

    if (Test-Path -LiteralPath $Downloads) {

        Start-Process `
            -FilePath "explorer.exe" `
            -ArgumentList "`"$Downloads`""
    }
    else {

        Show-AppMessage `
            "Downloads folder could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ---------------------------------------------------------
# Edit config button
# ---------------------------------------------------------

$ConfigButton.Add_Click({

    if (Test-Path -LiteralPath $ConfigPath) {

        Start-Process `
            -FilePath "notepad.exe" `
            -ArgumentList "`"$ConfigPath`""
    }
    else {

        Show-AppMessage `
            "config.json could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ---------------------------------------------------------
# Open log button
# ---------------------------------------------------------

$LogButton.Add_Click({

    try {

        if (!(Test-Path -LiteralPath $LogPath)) {

            New-Item `
                -ItemType File `
                -Path $LogPath `
                -Force |
                Out-Null
        }

        Start-Process `
            -FilePath "notepad.exe" `
            -ArgumentList "`"$LogPath`""

    }
    catch {

        Show-AppMessage `
            $_.Exception.Message `
            "Log Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ---------------------------------------------------------
# Open project folder button
# ---------------------------------------------------------

$ProjectButton.Add_Click({

    Start-Process `
        -FilePath "explorer.exe" `
        -ArgumentList "`"$ScriptDir`""
})

# ---------------------------------------------------------
# Enable startup
# ---------------------------------------------------------

$InstallButton.Add_Click({

    if (!(Test-Path -LiteralPath $InstallPath)) {

        Show-AppMessage `
            "Install.ps1 could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)

        return
    }

    try {

        & $InstallPath

        Show-AppMessage `
            "Automatic Windows startup has been enabled."

    }
    catch {

        Show-AppMessage `
            $_.Exception.Message `
            "Installer Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ---------------------------------------------------------
# Disable startup
# ---------------------------------------------------------

$UninstallButton.Add_Click({

    if (!(Test-Path -LiteralPath $UninstallPath)) {

        Show-AppMessage `
            "Uninstall.ps1 could not be found." `
            "Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)

        return
    }

    try {

        & $UninstallPath

        Show-AppMessage `
            "Automatic Windows startup has been disabled."

    }
    catch {

        Show-AppMessage `
            $_.Exception.Message `
            "Uninstall Error" `
            ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ---------------------------------------------------------
# Tray menu
# ---------------------------------------------------------

$TrayMenu =
    New-Object System.Windows.Forms.ContextMenuStrip

$ShowMenuItem =
    $TrayMenu.Items.Add(
        "Open AutoDownloadsOrganizer"
    )

$OrganizeMenuItem =
    $TrayMenu.Items.Add(
        "Organize Now"
    )

$Separator1 =
    New-Object System.Windows.Forms.ToolStripSeparator

$TrayMenu.Items.Add($Separator1) |
    Out-Null

$StartMenuItem =
    $TrayMenu.Items.Add(
        "Start Monitoring"
    )

$StopMenuItem =
    $TrayMenu.Items.Add(
        "Stop Monitoring"
    )

$Separator2 =
    New-Object System.Windows.Forms.ToolStripSeparator

$TrayMenu.Items.Add($Separator2) |
    Out-Null

$DownloadsMenuItem =
    $TrayMenu.Items.Add(
        "Open Downloads"
    )

$Separator3 =
    New-Object System.Windows.Forms.ToolStripSeparator

$TrayMenu.Items.Add($Separator3) |
    Out-Null

$ExitMenuItem =
    $TrayMenu.Items.Add(
        "Exit"
    )

$TrayIcon.ContextMenuStrip = $TrayMenu

# ---------------------------------------------------------
# Tray - Open app
# ---------------------------------------------------------

$ShowMenuItem.Add_Click({

    $Form.Show()

    $Form.WindowState =
        [System.Windows.Forms.FormWindowState]::Normal

    $Form.Activate()
})

# ---------------------------------------------------------
# Tray - Organize
# ---------------------------------------------------------

$OrganizeMenuItem.Add_Click({
    Start-DownloadsOrganization
})

# ---------------------------------------------------------
# Tray - Start monitoring
# ---------------------------------------------------------

$StartMenuItem.Add_Click({

    Start-DownloadsWatcher
})

# ---------------------------------------------------------
# Tray - Stop monitoring
# ---------------------------------------------------------

$StopMenuItem.Add_Click({

    Stop-DownloadsWatcher
})

# ---------------------------------------------------------
# Tray - Open Downloads
# ---------------------------------------------------------

$DownloadsMenuItem.Add_Click({

    $Downloads = Get-DownloadsPath

    if (Test-Path -LiteralPath $Downloads) {

        Start-Process `
            -FilePath "explorer.exe" `
            -ArgumentList "`"$Downloads`""
    }
})

# ---------------------------------------------------------
# Tray - Exit
# ---------------------------------------------------------

$ExitMenuItem.Add_Click({

    $Form.Tag = "Exit"

    $StatusTimer.Stop()

    $TrayIcon.Visible = $false
    $TrayIcon.Dispose()

    $Form.Close()
})

# ---------------------------------------------------------
# Tray icon double-click
# ---------------------------------------------------------

$TrayIcon.Add_DoubleClick({

    $Form.Show()

    $Form.WindowState =
        [System.Windows.Forms.FormWindowState]::Normal

    $Form.Activate()
})

# ---------------------------------------------------------
# Minimize to tray
# ---------------------------------------------------------

$Form.Add_Resize({

    if (
        $Form.WindowState -eq
        [System.Windows.Forms.FormWindowState]::Minimized
    ) {

        $Form.Hide()

        Show-TrayNotification `
            "AutoDownloadsOrganizer" `
            "The control center is still running in the system tray."
    }
})

# ---------------------------------------------------------
# Close button -> hide to tray
# ---------------------------------------------------------

$Form.Add_FormClosing({

    param(
        $Sender,
        $EventArgs
    )

    if ($Form.Tag -ne "Exit") {

        $EventArgs.Cancel = $true

        $Form.Hide()

        Show-TrayNotification `
            "AutoDownloadsOrganizer" `
            "The control center is still running in the system tray."
    }
})

# ---------------------------------------------------------
# Refresh watcher status automatically
# ---------------------------------------------------------

$StatusTimer =
    New-Object System.Windows.Forms.Timer

$StatusTimer.Interval = 3000

$StatusTimer.Add_Tick({

    Update-WatcherStatus
})

$StatusTimer.Start()

# ---------------------------------------------------------
# Initial status
# ---------------------------------------------------------

Update-WatcherStatus

# ---------------------------------------------------------
# Start Windows Forms application
# ---------------------------------------------------------

[System.Windows.Forms.Application]::EnableVisualStyles()

[System.Windows.Forms.Application]::Run($Form)

# ---------------------------------------------------------
# Cleanup
# ---------------------------------------------------------

$StatusTimer.Stop()
$StatusTimer.Dispose()
$OrganizerPollTimer.Stop()
$OrganizerPollTimer.Dispose()

if ($script:OrganizerProcess) {
    $script:OrganizerProcess.Dispose()
}

if ($TrayIcon) {

    $TrayIcon.Visible = $false
    $TrayIcon.Dispose()
}
