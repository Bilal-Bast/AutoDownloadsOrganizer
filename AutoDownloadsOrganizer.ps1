Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------
# AutoDownloadsOrganizer
# GUI + System Tray Control Center
# ---------------------------------------------------------

$ScriptDir = if ($PSScriptRoot) {
    $PSScriptRoot
}
elseif ($ScriptRoot) {
    $ScriptRoot
}
else {
    Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

$OrganizerPath = Join-Path $ScriptDir "Organize-Downloads.ps1"
$WatcherPath   = Join-Path $ScriptDir "Watch-Downloads.ps1"
$InstallPath   = Join-Path $ScriptDir "Install.ps1"
$UninstallPath = Join-Path $ScriptDir "Uninstall.ps1"
$ConfigPath    = Join-Path $ScriptDir "config.json"
$LogPath       = Join-Path $ScriptDir "organizer.log"
$HistoryPath   = Join-Path $ScriptDir "organization-history.jsonl"
$UndoPath      = Join-Path $ScriptDir "Undo-Last-Organization.ps1"
$IconPath      = Join-Path $ScriptDir "assets\AutoDownloadsOrganizer.ico"
$VersionPath   = Join-Path $ScriptDir "VERSION"
$AppVersion    = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { "6.0.0" }

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

function Get-OrganizationStats {
    $Result = [ordered]@{ Total = 0; Today = 0; Categories = @{} }
    if (!(Test-Path -LiteralPath $HistoryPath -PathType Leaf)) { return $Result }

    $Records = @(
        Get-Content -LiteralPath $HistoryPath -Encoding UTF8 | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $_ }
    )
    $Undone = @{}
    foreach ($Record in $Records | Where-Object { $_.action -eq "undo" -and $_.undoOf }) {
        $Undone[[string]$Record.undoOf] = $true
    }
    $Today = (Get-Date).Date
    foreach ($Record in $Records | Where-Object { $_.action -eq "move" }) {
        if ($Undone.ContainsKey([string]$Record.moveId)) { continue }
        $Result.Total++
        $Category = [string]$Record.category
        if (!$Result.Categories.ContainsKey($Category)) { $Result.Categories[$Category] = 0 }
        $Result.Categories[$Category]++
        try {
            if ([DateTime]::Parse([string]$Record.timestamp).ToLocalTime().Date -eq $Today) { $Result.Today++ }
        }
        catch { }
    }
    return $Result
}

function Update-StatisticsSummary {
    if (!$StatsLabel) { return }
    $Stats = Get-OrganizationStats
    $StatsLabel.Text = "Organized today: $($Stats.Today)    |    Total: $($Stats.Total)"
}

function Show-StatisticsDialog {
    $Stats = Get-OrganizationStats
    $Lines = @("Organized today: $($Stats.Today)", "Organized in total: $($Stats.Total)", "", "By category:")
    foreach ($Category in @($Stats.Categories.Keys | Sort-Object { -$Stats.Categories[$_] }, { $_ })) {
        $Lines += "  $Category  $($Stats.Categories[$Category])"
    }
    if ($Stats.Categories.Count -eq 0) { $Lines += "  No files organized yet." }
    Show-AppMessage ($Lines -join [Environment]::NewLine) "Organization Statistics"
}

function Test-SafeCategoryName {
    param([string]$Name)
    $Invalid = [System.IO.Path]::GetInvalidFileNameChars()
    return (
        ![string]::IsNullOrWhiteSpace($Name) -and
        $Name -eq $Name.Trim() -and
        $Name -notin @(".", "..") -and
        !$Name.Contains("\") -and !$Name.Contains("/") -and
        !$Name.EndsWith(".") -and
        $Name.IndexOfAny($Invalid) -lt 0 -and
        $Name -notmatch '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
    )
}

function Save-AppConfig {
    param($Config)
    $Config | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
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

function Save-CategoryDefinition {
    param([string]$CategoryName, [string]$ExtensionText)
    if (!(Test-SafeCategoryName $CategoryName)) {
        Show-AppMessage "Use a single, valid folder name for the category." "Invalid Category" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    }

    $Extensions = @(
        $ExtensionText -split '[,;\s]+' |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.ToLowerInvariant() }
    )
    foreach ($Extension in $Extensions) {
        if ($Extension -notmatch '^\.[a-z0-9][a-z0-9._+-]*$') {
            Show-AppMessage "Extensions must look like .png or .tar.gz." "Invalid Extension" ([System.Windows.Forms.MessageBoxIcon]::Warning)
            return $false
        }
    }
    if ($CategoryName -eq "Other" -and $Extensions.Count -gt 0) {
        Show-AppMessage "Other is the fallback category and cannot own extensions." "Required Category" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    }
    if (@($Extensions | Select-Object -Unique).Count -ne $Extensions.Count) {
        Show-AppMessage "Each extension can appear only once in a category." "Duplicate Extension" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    }

    $Config = Get-AppConfig
    if (!$Config -or !$Config.categories) {
        Show-AppMessage "config.json could not be read." "Configuration Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    foreach ($Category in $Config.categories.PSObject.Properties) {
        if ($Category.Name -eq $CategoryName) { continue }
        foreach ($ExistingExtension in @($Category.Value)) {
            if ($Extensions -contains ([string]$ExistingExtension).ToLowerInvariant()) {
                Show-AppMessage "The extension $ExistingExtension is already assigned to '$($Category.Name)'." "Duplicate Extension" ([System.Windows.Forms.MessageBoxIcon]::Warning)
                return $false
            }
        }
    }

    $CategoryProperty = $Config.categories.PSObject.Properties[$CategoryName]
    if (!$CategoryProperty) {
        Show-AppMessage "Select an existing category or add a new one first." "Category Not Found" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    }
    $CategoryProperty.Value = @($Extensions)
    Save-AppConfig $Config
    return $true
}

function Show-CategoryEditor {
    $Config = Get-AppConfig
    if (!$Config -or !$Config.categories) {
        Show-AppMessage "config.json could not be read." "Configuration Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $Editor = New-Object System.Windows.Forms.Form
    $Editor.Text = "Category Editor"
    $Editor.Size = New-Object System.Drawing.Size(570, 440)
    $Editor.StartPosition = "CenterParent"
    $Editor.FormBorderStyle = "FixedDialog"
    $Editor.MaximizeBox = $false
    $Editor.MinimizeBox = $false
    $Editor.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 28)
    $Editor.ForeColor = [System.Drawing.Color]::White
    $Editor.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $CategoryList = New-Object System.Windows.Forms.ListBox
    $CategoryList.Location = New-Object System.Drawing.Point(20, 20)
    $CategoryList.Size = New-Object System.Drawing.Size(190, 310)
    $CategoryList.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
    $CategoryList.ForeColor = [System.Drawing.Color]::White
    foreach ($Category in $Config.categories.PSObject.Properties) { [void]$CategoryList.Items.Add($Category.Name) }
    $Editor.Controls.Add($CategoryList)

    $NameLabel = New-Object System.Windows.Forms.Label
    $NameLabel.Text = "Category"
    $NameLabel.AutoSize = $true
    $NameLabel.Location = New-Object System.Drawing.Point(230, 24)
    $Editor.Controls.Add($NameLabel)

    $NameBox = New-Object System.Windows.Forms.TextBox
    $NameBox.Location = New-Object System.Drawing.Point(230, 48)
    $NameBox.Size = New-Object System.Drawing.Size(295, 26)
    $NameBox.ReadOnly = $true
    $Editor.Controls.Add($NameBox)

    $ExtensionsLabel = New-Object System.Windows.Forms.Label
    $ExtensionsLabel.Text = "Extensions (comma or space separated)"
    $ExtensionsLabel.AutoSize = $true
    $ExtensionsLabel.Location = New-Object System.Drawing.Point(230, 92)
    $Editor.Controls.Add($ExtensionsLabel)

    $ExtensionsBox = New-Object System.Windows.Forms.TextBox
    $ExtensionsBox.Multiline = $true
    $ExtensionsBox.ScrollBars = "Vertical"
    $ExtensionsBox.Location = New-Object System.Drawing.Point(230, 118)
    $ExtensionsBox.Size = New-Object System.Drawing.Size(295, 150)
    $Editor.Controls.Add($ExtensionsBox)

    $EditorStatus = New-Object System.Windows.Forms.Label
    $EditorStatus.Text = "Extensions must be unique across all categories."
    $EditorStatus.AutoSize = $true
    $EditorStatus.ForeColor = [System.Drawing.Color]::FromArgb(170, 170, 180)
    $EditorStatus.Location = New-Object System.Drawing.Point(230, 278)
    $Editor.Controls.Add($EditorStatus)

    $SaveCategoryButton = New-Object System.Windows.Forms.Button
    $SaveCategoryButton.Text = "Save Extensions"
    $SaveCategoryButton.Location = New-Object System.Drawing.Point(230, 315)
    $SaveCategoryButton.Size = New-Object System.Drawing.Size(140, 38)
    $Editor.Controls.Add($SaveCategoryButton)

    $NewNameBox = New-Object System.Windows.Forms.TextBox
    $NewNameBox.Location = New-Object System.Drawing.Point(20, 365)
    $NewNameBox.Size = New-Object System.Drawing.Size(190, 26)
    $Editor.Controls.Add($NewNameBox)

    $NewNameLabel = New-Object System.Windows.Forms.Label
    $NewNameLabel.Text = "New category name"
    $NewNameLabel.AutoSize = $true
    $NewNameLabel.Location = New-Object System.Drawing.Point(20, 342)
    $Editor.Controls.Add($NewNameLabel)

    $AddCategoryButton = New-Object System.Windows.Forms.Button
    $AddCategoryButton.Text = "Add Category"
    $AddCategoryButton.Location = New-Object System.Drawing.Point(230, 365)
    $AddCategoryButton.Size = New-Object System.Drawing.Size(140, 34)
    $Editor.Controls.Add($AddCategoryButton)

    $DeleteCategoryButton = New-Object System.Windows.Forms.Button
    $DeleteCategoryButton.Text = "Delete Category"
    $DeleteCategoryButton.Location = New-Object System.Drawing.Point(385, 365)
    $DeleteCategoryButton.Size = New-Object System.Drawing.Size(140, 34)
    $Editor.Controls.Add($DeleteCategoryButton)

    $CategoryList.Add_SelectedIndexChanged({
        if (!$CategoryList.SelectedItem) { return }
        $SelectedName = [string]$CategoryList.SelectedItem
        $CurrentConfig = Get-AppConfig
        $SelectedCategory = $CurrentConfig.categories.PSObject.Properties[$SelectedName]
        $NameBox.Text = $SelectedName
        $ExtensionsBox.Text = (@($SelectedCategory.Value) -join ", ")
    })
    $SaveCategoryButton.Add_Click({
        if (!$NameBox.Text) { Show-AppMessage "Select a category first."; return }
        if (Save-CategoryDefinition -CategoryName $NameBox.Text -ExtensionText $ExtensionsBox.Text) {
            $EditorStatus.Text = "Saved. Restart monitoring to apply watcher changes."
            Update-StatisticsSummary
        }
    })
    $AddCategoryButton.Add_Click({
        $NewName = $NewNameBox.Text.Trim()
        if (!(Test-SafeCategoryName $NewName)) { Show-AppMessage "Enter a valid single folder name." "Invalid Category" ([System.Windows.Forms.MessageBoxIcon]::Warning); return }
        $CurrentConfig = Get-AppConfig
        if ($CurrentConfig.categories.PSObject.Properties[$NewName]) { Show-AppMessage "That category already exists."; return }
        $CurrentConfig.categories | Add-Member -NotePropertyName $NewName -NotePropertyValue @()
        Save-AppConfig $CurrentConfig
        [void]$CategoryList.Items.Add($NewName)
        $CategoryList.SelectedItem = $NewName
        $EditorStatus.Text = "Added. Restart monitoring to apply watcher changes."
        $NewNameBox.Clear()
    })
    $DeleteCategoryButton.Add_Click({
        if (!$CategoryList.SelectedItem) { Show-AppMessage "Select a category first."; return }
        $SelectedName = [string]$CategoryList.SelectedItem
        if ($SelectedName -eq "Other") { Show-AppMessage "The Other category is required." "Required Category"; return }
        $Answer = [System.Windows.Forms.MessageBox]::Show("Delete '$SelectedName' from the category list? Existing files will stay where they are.", "Delete Category", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($Answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $CurrentConfig = Get-AppConfig
        $CurrentConfig.categories.PSObject.Properties.Remove($SelectedName)
        Save-AppConfig $CurrentConfig
        $CategoryList.Items.Remove($SelectedName)
        $NameBox.Clear()
        $ExtensionsBox.Clear()
        $EditorStatus.Text = "Deleted. Restart monitoring to apply watcher changes."
    })

    [void]$Editor.ShowDialog($Form)
    $Editor.Dispose()
}

# ---------------------------------------------------------
# Main form
# ---------------------------------------------------------

$Form = New-Object System.Windows.Forms.Form

$Form.Text = "AutoDownloadsOrganizer"
$Form.Size = New-Object System.Drawing.Size(570, 700)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedSingle"
$Form.MaximizeBox = $false

$Form.BackColor =
    [System.Drawing.Color]::FromArgb(25, 25, 28)

$Form.ForeColor =
    [System.Drawing.Color]::White

$Form.Font =
    New-Object System.Drawing.Font("Segoe UI", 9)

$Form.Icon = if (Test-Path -LiteralPath $IconPath) { New-Object System.Drawing.Icon($IconPath) } else { [System.Drawing.SystemIcons]::Application }

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

    $Button.FlatAppearance.BorderSize = 0

    $Button.FlatAppearance.BorderColor =
        [System.Drawing.Color]::FromArgb(70, 70, 75)

    $Button.BackColor = if ($Text -eq "Organize Now") {
        [System.Drawing.Color]::FromArgb(67, 97, 238)
    }
    else {
        [System.Drawing.Color]::FromArgb(44, 47, 55)
    }

    $Button.ForeColor =
        [System.Drawing.Color]::White

    $Button.Font =
        New-Object System.Drawing.Font("Segoe UI", 10)

    $Button.Cursor =
        [System.Windows.Forms.Cursors]::Hand

    $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(70, 75, 88)
    if ($Text -eq "Organize Now") {
        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(86, 115, 250)
    }

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
    -Text "Edit Categories" `
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

$UndoButton = New-AppButton `
    -Text "Undo Last Organization" `
    -X 30 `
    -Y 415

$StatisticsButton = New-AppButton `
    -Text "View Statistics" `
    -X 285 `
    -Y 415

$InstallButton = New-AppButton `
    -Text "Enable Windows Startup" `
    -X 30 `
    -Y 480

$UninstallButton = New-AppButton `
    -Text "Disable Windows Startup" `
    -X 285 `
    -Y 480

$AboutButton = New-AppButton `
    -Text "About / Version" `
    -X 285 `
    -Y 545

$AdvancedConfigButton = New-AppButton `
    -Text "Edit JSON Settings" `
    -X 30 `
    -Y 545

$StatsLabel = New-Object System.Windows.Forms.Label
$StatsLabel.AutoSize = $true
$StatsLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 185, 198)
$StatsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$StatsLabel.Location = New-Object System.Drawing.Point(30, 603)
$Form.Controls.Add($StatsLabel)

# ---------------------------------------------------------
# Footer
# ---------------------------------------------------------

$Footer = New-Object System.Windows.Forms.Label

$Footer.Text = "Version $AppVersion  |  Windows 10 / 11"

$Footer.AutoSize = $true

$Footer.ForeColor =
    [System.Drawing.Color]::FromArgb(130, 130, 135)

$Footer.Font =
    New-Object System.Drawing.Font("Segoe UI", 9)

$Footer.Location =
    New-Object System.Drawing.Point(30, 630)

$Form.Controls.Add($Footer)

# ---------------------------------------------------------
# Tray icon
# ---------------------------------------------------------

$TrayIcon = New-Object System.Windows.Forms.NotifyIcon

$TrayIcon.Icon = if (Test-Path -LiteralPath $IconPath) {
    New-Object System.Drawing.Icon($IconPath)
}
else {
    [System.Drawing.SystemIcons]::Application
}

$TrayIcon.Visible = $true

$TrayIcon.Text =
    "AutoDownloadsOrganizer"

# ---------------------------------------------------------
# Tray notification helper
# ---------------------------------------------------------

function Show-TrayNotification {

    param(
        [string]$Title,
        [string]$Message,
        [string]$Preference = "enabled"
    )

    try {
        $NotificationConfig = (Get-AppConfig).notifications
        if ($NotificationConfig -and $NotificationConfig.enabled -eq $false) { return }
        if (
            $Preference -ne "enabled" -and
            $NotificationConfig -and
            $NotificationConfig.PSObject.Properties[$Preference] -and
            $NotificationConfig.$Preference -eq $false
        ) { return }

        $DurationSeconds = 3
        if ($NotificationConfig -and $NotificationConfig.durationSeconds) {
            $DurationSeconds = [Math]::Max(1, [Math]::Min(10, [int]$NotificationConfig.durationSeconds))
        }

        $TrayIcon.BalloonTipTitle = $Title
        $TrayIcon.BalloonTipText = $Message

        $TrayIcon.BalloonTipIcon =
            [System.Windows.Forms.ToolTipIcon]::Info

        $TrayIcon.ShowBalloonTip($DurationSeconds * 1000)

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

    if ($script:UndoProcess) {
        try {
            $script:UndoProcess.Refresh()
            if (!$script:UndoProcess.HasExited) {
                $StartWatcherButton.Enabled = $false
                $StopWatcherButton.Enabled = $false
                if ($StartMenuItem) { $StartMenuItem.Enabled = $false }
                if ($StopMenuItem) { $StopMenuItem.Enabled = $false }
            }
        }
        catch { }
    }
}

# ---------------------------------------------------------
# Start watcher helper
# ---------------------------------------------------------

function Start-DownloadsWatcher {
    param([switch]$Quiet)

    if ($script:UndoProcess) {
        try {
            $script:UndoProcess.Refresh()
            if (!$script:UndoProcess.HasExited) {
                if (!$Quiet) { Show-AppMessage "Wait for undo to finish before changing monitoring." }
                return
            }
        }
        catch { }
    }

    if (Test-WatcherRunning) {

        Update-WatcherStatus

        if (!$Quiet) {
            Show-AppMessage "Real-time monitoring is already running."
        }

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

            if (!$Quiet) {
                Show-TrayNotification `
                    "Monitoring Started" `
                    "Your Downloads folder is now being monitored." `
                    -Preference "watcherStarted"
            }
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
    param([switch]$Quiet)

    if ($script:UndoProcess) {
        try {
            $script:UndoProcess.Refresh()
            if (!$script:UndoProcess.HasExited) {
                if (!$Quiet) { Show-AppMessage "Wait for undo to finish before changing monitoring." }
                return
            }
        }
        catch { }
    }

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

    if (!$Quiet) {
        Show-TrayNotification `
            "Monitoring Stopped" `
            "Real-time monitoring has been stopped." `
            -Preference "watcherStopped"
    }
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

    if ($script:UndoProcess) {
        try {
            $script:UndoProcess.Refresh()
            if (!$script:UndoProcess.HasExited) { Show-AppMessage "Undo is still in progress."; return }
        }
        catch { }
    }

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
        Update-StatisticsSummary

        if ($ExitCode -eq 0) {
            Show-TrayNotification `
                "Organization Complete" `
                "Your Downloads folder has been organized." `
                -Preference "organizationComplete"

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
                "Some files could not be organized. Check organizer.log." `
                -Preference "organizationFailed"

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

# ---------------------------------------------------------
# Undo and statistics
# ---------------------------------------------------------

$script:UndoProcess = $null
$script:RestartWatcherAfterUndo = $false
$UndoPollTimer = New-Object System.Windows.Forms.Timer
$UndoPollTimer.Interval = 500

function Resume-WatcherAfterUndo {
    if ($script:RestartWatcherAfterUndo) {
        $script:RestartWatcherAfterUndo = $false
        Start-DownloadsWatcher -Quiet
    }
}

function Start-UndoLastOrganization {
    if ($script:OrganizerProcess) {
        try {
            $script:OrganizerProcess.Refresh()
            if (!$script:OrganizerProcess.HasExited) { Show-AppMessage "Wait for organization to finish before undoing it."; return }
        }
        catch { }
    }
    if ($script:UndoProcess) {
        try {
            $script:UndoProcess.Refresh()
            if (!$script:UndoProcess.HasExited) { Show-AppMessage "Undo is already in progress."; return }
            $script:UndoProcess.Dispose()
            $script:UndoProcess = $null
        }
        catch { $script:UndoProcess = $null }
    }
    if (!(Test-Path -LiteralPath $UndoPath -PathType Leaf)) {
        Show-AppMessage "Undo-Last-Organization.ps1 could not be found." "Undo Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    try {
        $script:RestartWatcherAfterUndo = Test-WatcherRunning
        if ($script:RestartWatcherAfterUndo) {
            Stop-DownloadsWatcher -Quiet
            if (Test-WatcherRunning) {
                $script:RestartWatcherAfterUndo = $false
                Show-AppMessage "Monitoring could not be paused, so undo was not started." "Undo Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
        }
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$UndoPath`""
        $script:UndoProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $Arguments -WindowStyle Hidden -PassThru
        $UndoButton.Enabled = $false
        $UndoButton.Text = "Undoing..."
        if ($ExitMenuItem) { $ExitMenuItem.Enabled = $false }
        $UndoPollTimer.Start()
    }
    catch {
        Resume-WatcherAfterUndo
        Show-AppMessage $_.Exception.Message "Undo Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
        $UndoButton.Enabled = $true
        $UndoButton.Text = "Undo Last Organization"
    }
}

$UndoPollTimer.Add_Tick({
    if (!$script:UndoProcess) { $UndoPollTimer.Stop(); return }
    try {
        $script:UndoProcess.Refresh()
        if (!$script:UndoProcess.HasExited) { return }
        $ExitCode = $script:UndoProcess.ExitCode
        $script:UndoProcess.Dispose()
        $script:UndoProcess = $null
        $UndoPollTimer.Stop()
        $UndoButton.Enabled = $true
        $UndoButton.Text = "Undo Last Organization"
        if ($ExitMenuItem) { $ExitMenuItem.Enabled = $true }
        Update-StatisticsSummary
        Update-WatcherStatus
        Resume-WatcherAfterUndo
        if ($ExitCode -eq 0) {
            Show-AppMessage "The most recent organization batch was restored." "Undo Complete"
        }
        elseif ($ExitCode -eq 3) {
            Show-AppMessage "There are no organized files left to undo." "Nothing to Undo"
        }
        else {
            Show-AppMessage "Undo could not restore every file. Review organizer.log for details." "Undo Needs Attention" ([System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
    catch {
        $UndoPollTimer.Stop()
        $script:UndoProcess = $null
        $UndoButton.Enabled = $true
        $UndoButton.Text = "Undo Last Organization"
        if ($ExitMenuItem) { $ExitMenuItem.Enabled = $true }
        Resume-WatcherAfterUndo
        Show-AppMessage $_.Exception.Message "Undo Error" ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$UndoButton.Add_Click({ Start-UndoLastOrganization })
$StatisticsButton.Add_Click({ Show-StatisticsDialog })

$AboutButton.Add_Click({
    $AboutText = @(
        "AutoDownloadsOrganizer $AppVersion",
        "A lightweight Windows Downloads folder organizer.",
        "",
        "Features: category rules, real-time monitoring, date sorting, undo history, and signature detection.",
        "PowerShell 5.1  |  Windows 10 / 11  |  MIT License"
    ) -join [Environment]::NewLine
    Show-AppMessage $AboutText "About AutoDownloadsOrganizer"
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
# Category editor button
# ---------------------------------------------------------

$ConfigButton.Add_Click({
    Show-CategoryEditor
})

$AdvancedConfigButton.Add_Click({
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
            "The control center is still running in the system tray." `
            -Preference "windowHidden"
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
            "The control center is still running in the system tray." `
            -Preference "windowHidden"
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
    Update-StatisticsSummary
})

$StatusTimer.Start()

# ---------------------------------------------------------
# Initial status
# ---------------------------------------------------------

Update-WatcherStatus
Update-StatisticsSummary

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
$UndoPollTimer.Stop()
$UndoPollTimer.Dispose()

if ($script:OrganizerProcess) {
    $script:OrganizerProcess.Dispose()
}

if ($script:UndoProcess) {
    $script:UndoProcess.Dispose()
}

if ($TrayIcon) {

    $TrayIcon.Visible = $false
    $TrayIcon.Dispose()
}
