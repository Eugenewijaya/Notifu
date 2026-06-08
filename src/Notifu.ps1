param(
    [switch]$Background,
    [switch]$Once,
    [switch]$ListVoices,
    [switch]$OpenSettings
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot "Notifu.Core.psm1"
$uiModulePath = Join-Path $PSScriptRoot "Notifu.UI.psm1"
Import-Module $modulePath -Force
Import-Module $uiModulePath -Force

if ($ListVoices) {
    Get-NotifuInstalledVoices | Format-Table -AutoSize
    return
}

Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    try {
        Write-NotifuLog -Level "error" -Message "Unhandled UI exception: $($eventArgs.Exception.Message)"
    } catch {}
})

$settingsPath = Join-Path $root "config\notifu.settings.json"
$script:settings = Get-NotifuSettings -Path $settingsPath

if ($OpenSettings) {
    Show-NotifuSettingsWindow -SettingsPath $settingsPath
    return
}

$access = Request-NotifuNotificationAccess
Write-NotifuLog -Message "Notification access: $access"

$state = [ordered]@{
    Seen = @{}
    LatestNotification = $null
    LatestAnalysis = $null
    LatestVoiceCommand = $null
    Paused = $false
    VoiceMuted = $false
    LastPopupAt = $null
}

if ($script:settings.listener.ignoreExistingOnStartup) {
    try {
        foreach ($raw in Get-NotifuRawNotifications) {
            $existing = ConvertTo-NotifuNotification -UserNotification $raw
            if (Test-NotifuTrackedNotification -Notification $existing -Settings $script:settings) {
                $state.Seen[$existing.UniqueKey] = (Get-Date)
            }
        }
        Write-NotifuLog -Message "Seeded existing tracked notifications: $($state.Seen.Count)"
    } catch {
        Write-NotifuLog -Level "warn" -Message "Unable to seed existing notifications: $($_.Exception.Message)"
    }
}

function Get-NotifuAppIcon {
    $iconPath = Join-Path $root "assets\notifu-app-icon.ico"
    if (Test-Path -LiteralPath $iconPath) {
        return New-Object System.Drawing.Icon $iconPath
    }

    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(42, 157, 143))
    $graphics.FillEllipse($brush, 2, 2, 28, 28)
    $font = New-Object System.Drawing.Font "Segoe UI", 15, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $textBrush = [System.Drawing.Brushes]::White
    $graphics.DrawString("N", $font, $textBrush, 9, 6)
    $iconHandle = $bitmap.GetHicon()
    return [System.Drawing.Icon]::FromHandle($iconHandle)
}

function Set-NotifuClipboard {
    param([string]$Text)
    if ($Text) {
        [System.Windows.Forms.Clipboard]::SetText($Text)
    }
}

function Invoke-NotifuAppSpeech {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [switch]$Async,

        [switch]$Force
    )

    if ($state.VoiceMuted -and -not $Force) {
        Write-NotifuLog -Message "Speech skipped because voice is muted."
        return
    }

    Invoke-NotifuSpeech -Text $Text -Settings $script:settings -Async:$Async
}

function Invoke-NotifuVoiceCommandFromContext {
    try {
        $listenResult = Read-NotifuVoiceCommand -Settings $script:settings
        if ($listenResult.Status -eq "disabled") {
            Invoke-NotifuAppSpeech -Text "Voice command belum aktif di settings." -Async -Force
            return
        }

        if ($listenResult.Status -ne "ok" -or -not $listenResult.Text) {
            Invoke-NotifuAppSpeech -Text "Aku belum menangkap perintahnya. Coba tekan voice lagi dan bicara sedikit lebih jelas." -Async -Force
            return
        }

        $state.LatestVoiceCommand = $listenResult.Text
        $action = Get-NotifuVoiceCommandAction `
            -CommandText $listenResult.Text `
            -Notification $state.LatestNotification `
            -Analysis $state.LatestAnalysis `
            -Settings $script:settings

        switch ($action.Action) {
            "open_app" {
                [void](Open-NotifuNotificationApp -Notification $state.LatestNotification)
            }
            "copy_reply" {
                if ($state.LatestAnalysis -and $state.LatestAnalysis.suggestedReply) {
                    Set-NotifuClipboard -Text $state.LatestAnalysis.suggestedReply
                }
            }
            "pause" {
                $state.Paused = $true
                if ($script:pauseItem) { $script:pauseItem.Text = "Resume" }
                if ($script:statusItem) { $script:statusItem.Text = "Notifu pause" }
            }
            "resume" {
                $state.Paused = $false
                if ($script:pauseItem) { $script:pauseItem.Text = "Pause" }
                if ($script:statusItem) { $script:statusItem.Text = "Notifu aktif" }
            }
            "dismiss" {
                Close-NotifuAssistantPopup
            }
            "hide_pet" {
                Set-NotifuDesktopPetVisible -Visible $false
            }
            "show_pet" {
                [void](Show-NotifuDesktopPet -Settings $script:settings)
                Set-NotifuDesktopPetVisible -Visible $true
            }
            "voice_on" {
                $state.VoiceMuted = $false
            }
        }

        if ($action.Response) {
            try {
                Set-NotifuDesktopPetBubble -Text $action.Response -Expression "talking" -Settings $script:settings
            } catch {}

            Invoke-NotifuAppSpeech -Text $action.Response -Async -Force
        }

        if ($action.Action -eq "voice_off") {
            $state.VoiceMuted = $true
        }
    } catch {
        Write-NotifuLog -Level "error" -Message "Voice command action failed: $($_.Exception.Message)"
        Invoke-NotifuAppSpeech -Text "Aduh, voice command-ku kepeleset error. Detailnya sudah aku tulis di log." -Async -Force
    }
}

function Invoke-NotifuNotificationCycle {
    if ($state.Paused) {
        return
    }

    try {
        $rawItems = Get-NotifuRawNotifications
        foreach ($raw in $rawItems) {
            $notification = ConvertTo-NotifuNotification -UserNotification $raw
            if (-not (Test-NotifuTrackedNotification -Notification $notification -Settings $script:settings)) {
                continue
            }

            if ($state.Seen.Contains($notification.UniqueKey)) {
                $seenAt = [datetime]$state.Seen[$notification.UniqueKey]
                if (((Get-Date) - $seenAt).TotalMinutes -lt [double]$script:settings.listener.dedupeMinutes) {
                    continue
                }
            }

            $state.Seen[$notification.UniqueKey] = (Get-Date)
            $analysis = Get-NotifuAnalysis -Notification $notification -Settings $script:settings
            $state.LatestNotification = $notification
            $state.LatestAnalysis = $analysis

            Write-NotifuLog -Message ("Notification from {0} / {1}: {2}" -f $notification.AppName, $analysis.sender, $analysis.summary)
            $cooldownSeconds = [Math]::Max(0, [int]$script:settings.listener.popupCooldownSeconds)
            if ($state.LastPopupAt -and (((Get-Date) - [datetime]$state.LastPopupAt).TotalSeconds -lt $cooldownSeconds)) {
                Write-NotifuLog -Message ("Popup suppressed by cooldown for notification from {0}" -f $analysis.sender)
                continue
            }

            $state.LastPopupAt = Get-Date
            if ($script:settings.ui.useCustomPopup) {
                [void](Show-NotifuAssistantPopup `
                    -Analysis $analysis `
                    -Settings $script:settings `
                    -OnOpenApp { [void](Open-NotifuNotificationApp -Notification $state.LatestNotification) } `
                    -OnCopyReply {
                        if ($state.LatestAnalysis -and $state.LatestAnalysis.suggestedReply) {
                            Set-NotifuClipboard -Text $state.LatestAnalysis.suggestedReply
                        }
                    } `
                    -OnSpeakAgain {
                        if ($state.LatestAnalysis -and $state.LatestAnalysis.announcement) {
                            Invoke-NotifuAppSpeech -Text $state.LatestAnalysis.announcement -Async
                        }
                    } `
                    -OnVoiceCommand { Invoke-NotifuVoiceCommandFromContext })
            }

            try {
                Set-NotifuDesktopPetBubble -Text $analysis.announcement -Expression $analysis.expression -Settings $script:settings
            } catch {
                Write-NotifuLog -Level "warn" -Message "Desktop pet bubble failed: $($_.Exception.Message)"
            }

            Invoke-NotifuAppSpeech -Text $analysis.announcement -Async

            $dedupeCutoff = (Get-Date).AddMinutes(-1 * [double]$script:settings.listener.dedupeMinutes)
            $oldKeys = @($state.Seen.GetEnumerator() | Where-Object { [datetime]$_.Value -lt $dedupeCutoff } | Select-Object -ExpandProperty Key)
            foreach ($key in $oldKeys) {
                $state.Seen.Remove($key)
            }
        }
    } catch {
        Write-NotifuLog -Level "error" -Message $_.Exception.Message
    }
}

if ($Once) {
    Invoke-NotifuNotificationCycle
    return
}

$script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
$script:trayIcon.Icon = Get-NotifuAppIcon
$script:trayIcon.Text = "Notifu - AI notification assistant"
$script:trayIcon.Visible = [bool]$script:settings.ui.showTrayIcon

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:statusItem.Text = "Notifu aktif"
$script:statusItem.Enabled = $false
[void]$menu.Items.Add($script:statusItem)

$script:pauseItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:pauseItem.Text = "Pause"
$script:pauseItem.Add_Click({
    $state.Paused = -not $state.Paused
    $script:pauseItem.Text = if ($state.Paused) { "Resume" } else { "Pause" }
    $script:statusItem.Text = if ($state.Paused) { "Notifu pause" } else { "Notifu aktif" }
})
[void]$menu.Items.Add($script:pauseItem)

$openSourceItem = New-Object System.Windows.Forms.ToolStripMenuItem
$openSourceItem.Text = "Buka aplikasi notifikasi"
$openSourceItem.Add_Click({ [void](Open-NotifuNotificationApp -Notification $state.LatestNotification) })
[void]$menu.Items.Add($openSourceItem)

$copyReplyItem = New-Object System.Windows.Forms.ToolStripMenuItem
$copyReplyItem.Text = "Copy draft balasan terakhir"
$copyReplyItem.Add_Click({
    if ($state.LatestAnalysis -and $state.LatestAnalysis.suggestedReply) {
        Set-NotifuClipboard -Text $state.LatestAnalysis.suggestedReply
        [System.Media.SystemSounds]::Asterisk.Play()
    }
})
[void]$menu.Items.Add($copyReplyItem)

$speakAgainItem = New-Object System.Windows.Forms.ToolStripMenuItem
$speakAgainItem.Text = "Bacakan ulang terakhir"
$speakAgainItem.Add_Click({
    if ($state.LatestAnalysis -and $state.LatestAnalysis.announcement) {
        Invoke-NotifuAppSpeech -Text $state.LatestAnalysis.announcement -Async
    }
})
[void]$menu.Items.Add($speakAgainItem)

$voiceCommandItem = New-Object System.Windows.Forms.ToolStripMenuItem
$voiceCommandItem.Text = "Dengarkan voice command"
$voiceCommandItem.Add_Click({ Invoke-NotifuVoiceCommandFromContext })
[void]$menu.Items.Add($voiceCommandItem)

$settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem
$settingsItem.Text = "Buka settings"
$settingsItem.Add_Click({
    Show-NotifuSettingsWindow -SettingsPath $settingsPath
    $script:settings = Get-NotifuSettings -Path $settingsPath
    $timer.Interval = [Math]::Max(1, [int]$script:settings.listener.pollSeconds) * 1000
})
[void]$menu.Items.Add($settingsItem)

$logItem = New-Object System.Windows.Forms.ToolStripMenuItem
$logItem.Text = "Buka log"
$logItem.Add_Click({
    $logPath = Join-Path $root "logs\notifu.log"
    if (-not (Test-Path -LiteralPath $logPath)) {
        New-Item -ItemType File -Force -Path $logPath | Out-Null
    }
    Start-Process "notepad.exe" -ArgumentList "`"$logPath`""
})
[void]$menu.Items.Add($logItem)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "Exit"
$exitItem.Add_Click({
    $script:trayIcon.Visible = $false
    $script:trayIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
[void]$menu.Items.Add($exitItem)

$script:trayIcon.ContextMenuStrip = $menu
$script:trayIcon.Add_DoubleClick({ [void](Open-NotifuNotificationApp -Notification $state.LatestNotification) })

try {
    if ($script:settings.ui.enableDesktopPet) {
        [void](Show-NotifuDesktopPet -Settings $script:settings)
    }
} catch {
    Write-NotifuLog -Level "warn" -Message "Desktop pet failed to start: $($_.Exception.Message)"
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(1, [int]$script:settings.listener.pollSeconds) * 1000
$timer.Add_Tick({ Invoke-NotifuNotificationCycle })
$timer.Start()

Invoke-NotifuNotificationCycle
Write-NotifuLog -Message "Notifu tray app started."
[System.Windows.Forms.Application]::Run()
