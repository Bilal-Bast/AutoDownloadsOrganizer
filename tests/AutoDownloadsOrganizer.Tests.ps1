BeforeAll {
    $script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:PowerShellExe = if ($PSVersionTable.PSEdition -eq "Core") {
        Join-Path $PSHOME "pwsh.exe"
    }
    else {
        Join-Path $PSHOME "powershell.exe"
    }

    function New-TestProject {
        $Root = Join-Path `
            ([System.IO.Path]::GetTempPath()) `
            ("AutoDownloadsOrganizer-Test-" + [guid]::NewGuid().ToString("N"))

        $ProjectDirectory = Join-Path $Root "App"
        $Downloads = Join-Path $Root "Downloads"
        New-Item -ItemType Directory -Path $ProjectDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $Downloads -Force | Out-Null

        foreach ($FileName in @(
            "Organize-Downloads.ps1",
            "Watch-Downloads.ps1",
            "config.json"
        )) {
            Copy-Item `
                -LiteralPath (Join-Path $script:RepositoryRoot $FileName) `
                -Destination $ProjectDirectory
        }

        $ConfigPath = Join-Path $ProjectDirectory "config.json"
        $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $Config.downloadsPath = $Downloads
        $Config.watcher.checkIntervalMilliseconds = 50
        $Config.watcher.postReadyDelayMilliseconds = 0
        $Config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

        return [pscustomobject]@{
            Root = $Root
            ProjectDirectory = $ProjectDirectory
            Downloads = $Downloads
            OrganizerPath = Join-Path $ProjectDirectory "Organize-Downloads.ps1"
            WatcherPath = Join-Path $ProjectDirectory "Watch-Downloads.ps1"
            LogPath = Join-Path $ProjectDirectory "organizer.log"
        }
    }

    function Set-TestProjectConfig {
        param(
            [Parameter(Mandatory = $true)]
            [psobject]$Project,

            [Parameter(Mandatory = $true)]
            [psobject]$Config
        )

        $ConfigPath = Join-Path $Project.ProjectDirectory "config.json"
        $Config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    }

    function Invoke-TestOrganizer {
        param(
            [Parameter(Mandatory = $true)]
            [psobject]$Project,

            [string[]]$Arguments = @()
        )

        $ProcessArguments = @(
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $Project.OrganizerPath
        ) + $Arguments

        $Output = & $script:PowerShellExe @ProcessArguments 2>&1
        $ExitCode = $LASTEXITCODE

        return [pscustomobject]@{
            ExitCode = $ExitCode
            Output = @($Output) -join [Environment]::NewLine
        }
    }
}

Describe "AutoDownloadsOrganizer file organization" {
    BeforeEach {
        $script:TestProject = New-TestProject
    }

    AfterEach {
        if ($script:TestProject -and (Test-Path -LiteralPath $script:TestProject.Root)) {
            Remove-Item -LiteralPath $script:TestProject.Root -Recurse -Force
        }
    }

    It "routes Minecraft package extensions to the configured Java and Minecraft category" {
        $SourcePath = Join-Path $script:TestProject.Downloads "resource-pack.mcpack"
        New-Item -ItemType File -Path $SourcePath | Out-Null

        $Result = Invoke-TestOrganizer -Project $script:TestProject

        $Result.ExitCode | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $script:TestProject.Downloads "Java & Minecraft\resource-pack.mcpack")) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $script:TestProject.Downloads "Game Files\resource-pack.mcpack")) | Should -BeFalse
    }

    It "adds a numeric suffix when a destination file already exists" {
        $DocumentsPath = Join-Path $script:TestProject.Downloads "Documents"
        New-Item -ItemType Directory -Path $DocumentsPath | Out-Null
        Set-Content -LiteralPath (Join-Path $DocumentsPath "report.txt") -Value "existing"
        Set-Content -LiteralPath (Join-Path $script:TestProject.Downloads "report.txt") -Value "new"

        $Result = Invoke-TestOrganizer -Project $script:TestProject

        $Result.ExitCode | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $DocumentsPath "report.txt") -Raw).Trim() | Should -Be "existing"
        (Get-Content -LiteralPath (Join-Path $DocumentsPath "report (1).txt") -Raw).Trim() | Should -Be "new"
    }

    It "rejects a single-file request outside the configured Downloads root" {
        $OutsidePath = Join-Path $script:TestProject.Root "outside.txt"
        Set-Content -LiteralPath $OutsidePath -Value "keep me"

        $Result = Invoke-TestOrganizer `
            -Project $script:TestProject `
            -Arguments @("-FilePath", $OutsidePath)

        $Result.ExitCode | Should -Be 1
        (Test-Path -LiteralPath $OutsidePath) | Should -BeTrue
    }

    It "rejects category names that could escape the Downloads root" {
        $ConfigPath = Join-Path $script:TestProject.ProjectDirectory "config.json"
        $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $Config.categories = [ordered]@{
            "..\Outside" = @(".txt")
            Other = @()
        }
        Set-TestProjectConfig -Project $script:TestProject -Config $Config

        $SourcePath = Join-Path $script:TestProject.Downloads "unsafe.txt"
        New-Item -ItemType File -Path $SourcePath | Out-Null
        $EscapedDestination = Join-Path $script:TestProject.Root "Outside\unsafe.txt"

        $Result = Invoke-TestOrganizer -Project $script:TestProject

        $Result.ExitCode | Should -Be 1
        (Test-Path -LiteralPath $SourcePath) | Should -BeTrue
        (Test-Path -LiteralPath $EscapedDestination) | Should -BeFalse
    }
}

Describe "AutoDownloadsOrganizer watcher" {
    BeforeEach {
        $script:TestProject = New-TestProject
    }

    AfterEach {
        if ($script:TestProject -and (Test-Path -LiteralPath $script:TestProject.Root)) {
            Remove-Item -LiteralPath $script:TestProject.Root -Recurse -Force
        }
    }

    It "retries a file that is locked while it is being created" {
        $OtherWatchers = @(
            Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProcessId -ne $PID -and
                    $_.CommandLine -and
                    $_.CommandLine -match "(?i)Watch-Downloads\.ps1"
                }
        )

        if ($OtherWatchers.Count -gt 0) {
            Set-ItResult -Skipped -Because "another AutoDownloadsOrganizer watcher is already running"
            return
        }

        $StdOutPath = Join-Path $script:TestProject.Root "watcher.stdout.log"
        $StdErrPath = Join-Path $script:TestProject.Root "watcher.stderr.log"
        $WatcherArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($script:TestProject.WatcherPath)`""
        $WatcherProcess = $null
        $FileStream = $null

        try {
            $WatcherProcess = Start-Process `
                -FilePath $script:PowerShellExe `
                -ArgumentList $WatcherArguments `
                -WindowStyle Hidden `
                -RedirectStandardOutput $StdOutPath `
                -RedirectStandardError $StdErrPath `
                -PassThru

            $StartupDeadline = (Get-Date).AddSeconds(10)
            $WatcherStarted = $false

            while ((Get-Date) -lt $StartupDeadline) {
                if ($WatcherProcess.HasExited) {
                    break
                }

                if (Test-Path -LiteralPath $script:TestProject.LogPath) {
                    $LogContents = Get-Content -LiteralPath $script:TestProject.LogPath -Raw
                    if ($LogContents -match "V\d+ watcher started") {
                        $WatcherStarted = $true
                        break
                    }
                }

                Start-Sleep -Milliseconds 100
            }

            $WatcherStarted | Should -BeTrue

            $SourcePath = Join-Path $script:TestProject.Downloads "delayed.txt"
            $FileStream = [System.IO.File]::Open(
                $SourcePath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes("download still in progress")
            $FileStream.Write($Bytes, 0, $Bytes.Length)
            $FileStream.Flush()
            Start-Sleep -Milliseconds 800
            $FileStream.Dispose()
            $FileStream = $null

            $DestinationPath = Join-Path $script:TestProject.Downloads "Documents\delayed.txt"
            $MoveDeadline = (Get-Date).AddSeconds(20)

            while (!(Test-Path -LiteralPath $DestinationPath) -and (Get-Date) -lt $MoveDeadline) {
                Start-Sleep -Milliseconds 100
            }

            (Test-Path -LiteralPath $DestinationPath) | Should -BeTrue
            (Get-Content -LiteralPath $script:TestProject.LogPath -Raw) | Should -Match "retry queued: delayed.txt"
        }
        finally {
            if ($FileStream) {
                $FileStream.Dispose()
            }

            if ($WatcherProcess -and !$WatcherProcess.HasExited) {
                $WatcherProcess.Kill()
                [void]$WatcherProcess.WaitForExit(5000)
            }
        }
    }
}
