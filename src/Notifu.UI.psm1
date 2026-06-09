Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ActivePopup = $null
$script:PopupContext = $null
$script:PetContext = $null

function Resolve-NotifuPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path (Split-Path -Parent $PSScriptRoot) $Path)
}

function Get-NotifuImage {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $image = [System.Drawing.Image]::FromStream($stream)
        return $image.Clone()
    } finally {
        $stream.Dispose()
    }
}

function Get-NotifuProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value -and [string]$property.Value -ne "") {
        return $property.Value
    }

    return $Default
}

function Get-NotifuExpressionAssetPath {
    param(
        $Settings,
        [string]$Expression = "happy"
    )

    $expressionImages = Get-NotifuProperty -Object $Settings.ui -Name "expressionImages" -Default $null
    if ($expressionImages) {
        $path = [string](Get-NotifuProperty -Object $expressionImages -Name $Expression -Default "")
        if ($path) {
            $resolved = Resolve-NotifuPath -Path $path
            if (Test-Path -LiteralPath $resolved) {
                return $resolved
            }
        }
    }

    $fallback = [string](Get-NotifuProperty -Object $Settings.ui -Name "avatarImagePath" -Default "assets\notifu-chibi-avatar-cutout.png")
    return (Resolve-NotifuPath -Path $fallback)
}

function New-NotifuRoundedRegion {
    param(
        [int]$Width,
        [int]$Height,
        [int]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    $rect = New-Object System.Drawing.Rectangle 0, 0, $diameter, $diameter
    $path.AddArc($rect, 180, 90)
    $rect.X = $Width - $diameter
    $path.AddArc($rect, 270, 90)
    $rect.Y = $Height - $diameter
    $path.AddArc($rect, 0, 90)
    $rect.X = 0
    $path.AddArc($rect, 90, 90)
    $path.CloseFigure()
    return New-Object System.Drawing.Region $path
}

function Close-NotifuAssistantPopup {
    if ($script:ActivePopup -and -not $script:ActivePopup.IsDisposed) {
        $script:ActivePopup.Close()
    }
}

function Show-NotifuAssistantPopup {
    param(
        [Parameter(Mandatory = $true)]
        $Analysis,

        [Parameter(Mandatory = $true)]
        $Settings,

        [scriptblock]$OnOpenApp,

        [scriptblock]$OnOpenWhatsApp,

        [scriptblock]$OnCopyReply,

        [scriptblock]$OnSpeakAgain,

        [scriptblock]$OnVoiceCommand,

        [switch]$NoShow
    )

    if (-not $OnOpenApp -and $OnOpenWhatsApp) {
        $OnOpenApp = $OnOpenWhatsApp
    }

    Close-NotifuAssistantPopup

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $width = [int]$Settings.ui.popupWidth
    $height = [int]$Settings.ui.popupHeight
    $targetX = $screen.Right - $width - 34
    $targetY = $screen.Top + [Math]::Max(54, [int]($screen.Height * 0.14))
    $targetX = [Math]::Max($screen.Left + 18, $targetX)
    $targetY = [Math]::Min($screen.Bottom - $height - 28, $targetY)
    $startX = $screen.Right + 28

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Notifu"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.Size = New-Object System.Drawing.Size $width, $height
    $form.Location = New-Object System.Drawing.Point $startX, $targetY
    $form.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 252)
    $form.Opacity = 0
    $form.Region = New-NotifuRoundedRegion -Width $width -Height $height -Radius 22

    $border = New-Object System.Windows.Forms.Panel
    $border.Dock = [System.Windows.Forms.DockStyle]::Fill
    $border.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 252)
    $form.Controls.Add($border)

    $avatar = New-Object System.Windows.Forms.PictureBox
    $avatar.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
    $avatar.Size = New-Object System.Drawing.Size 112, 112
    $avatar.Location = New-Object System.Drawing.Point 14, 54
    $avatar.BackColor = [System.Drawing.Color]::Transparent

    $expression = [string](Get-NotifuProperty -Object $Analysis -Name "expression" -Default "happy")
    $avatarPath = Get-NotifuExpressionAssetPath -Settings $Settings -Expression $expression
    $talkPath = Get-NotifuExpressionAssetPath -Settings $Settings -Expression "talking"
    $avatarState = [pscustomobject]@{
        Base = $null
        Talk = $null
        Current = "base"
    }
    if (Test-Path -LiteralPath $avatarPath) {
        $avatarState.Base = Get-NotifuImage -Path $avatarPath
    }
    if ($talkPath -and (Test-Path -LiteralPath $talkPath)) {
        $avatarState.Talk = Get-NotifuImage -Path $talkPath
    }
    $avatar.Tag = $avatarState
    $avatar.Add_Paint({
        param($sender, $eventArgs)
        $state = $sender.Tag
        $image = if ($state -and $state.Current -eq "talk" -and $state.Talk) { $state.Talk } elseif ($state) { $state.Base } else { $null }
        if ($image) {
            $graphics = $eventArgs.Graphics
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.Clear($sender.BackColor)

            $scale = [Math]::Min($sender.Width / $image.Width, $sender.Height / $image.Height)
            $drawWidth = [int]($image.Width * $scale)
            $drawHeight = [int]($image.Height * $scale)
            $drawX = [int](($sender.Width - $drawWidth) / 2)
            $drawY = [int](($sender.Height - $drawHeight) / 2)
            $graphics.DrawImage($image, (New-Object System.Drawing.Rectangle $drawX, $drawY, $drawWidth, $drawHeight))
        }
    })
    $border.Controls.Add($avatar)

    $title = New-Object System.Windows.Forms.Label
    $title.AutoSize = $false
    $title.Location = New-Object System.Drawing.Point 132, 16
    $title.Size = New-Object System.Drawing.Size ($width - 170), 22
    $title.Font = New-Object System.Drawing.Font "Segoe UI Semibold", 9.8
    $title.ForeColor = [System.Drawing.Color]::FromArgb(30, 75, 90)
    $appName = [string](Get-NotifuProperty -Object $Analysis -Name "appName" -Default "Notifikasi")
    $title.Text = "$appName - $($Analysis.sender)"
    $border.Controls.Add($title)

    $bubble = New-Object System.Windows.Forms.Panel
    $bubble.Location = New-Object System.Drawing.Point 126, 42
    $bubble.Size = New-Object System.Drawing.Size ($width - 152), 86
    $bubble.BackColor = [System.Drawing.Color]::FromArgb(236, 253, 247)
    $bubble.Region = New-NotifuRoundedRegion -Width $bubble.Width -Height $bubble.Height -Radius 16
    $border.Controls.Add($bubble)

    $message = New-Object System.Windows.Forms.Label
    $message.AutoSize = $false
    $message.Location = New-Object System.Drawing.Point 13, 10
    $message.Size = New-Object System.Drawing.Size ($bubble.Width - 26), ($bubble.Height - 18)
    $message.Font = New-Object System.Drawing.Font "Segoe UI", 8.9
    $message.ForeColor = [System.Drawing.Color]::FromArgb(30, 37, 42)
    $message.Text = ""
    $bubble.Controls.Add($message)

    $hint = New-Object System.Windows.Forms.Label
    $hint.AutoSize = $false
    $hint.Location = New-Object System.Drawing.Point 132, 132
    $hint.Size = New-Object System.Drawing.Size ($width - 158), 18
    $hint.Font = New-Object System.Drawing.Font "Segoe UI", 8.6
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(102, 86, 112)
    $hint.Text = "Urgensi: $($Analysis.urgency)  |  Aksi: $($Analysis.actionHint)"
    $border.Controls.Add($hint)

    $openButton = New-Object System.Windows.Forms.Button
    $openButton.Text = "Buka App"
    $openButton.Location = New-Object System.Drawing.Point 132, 154
    $openButton.Size = New-Object System.Drawing.Size 78, 29
    $openButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $openButton.BackColor = [System.Drawing.Color]::FromArgb(36, 140, 128)
    $openButton.ForeColor = [System.Drawing.Color]::White
    $openButton.Add_Click({
        try {
            $ctx = $script:PopupContext
            if ($ctx -and $ctx.OnOpenApp) {
                & $ctx.OnOpenApp
            }
        } catch {
            Write-NotifuLog -Level "error" -Message "Popup open app action failed: $($_.Exception.Message)"
        }
    })
    $border.Controls.Add($openButton)

    $replyButton = New-Object System.Windows.Forms.Button
    $replyButton.Text = "Copy"
    $replyButton.Location = New-Object System.Drawing.Point 218, 154
    $replyButton.Size = New-Object System.Drawing.Size 62, 29
    $replyButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $replyButton.BackColor = [System.Drawing.Color]::White
    $replyButton.ForeColor = [System.Drawing.Color]::FromArgb(31, 72, 67)
    $replyButton.Add_Click({
        try {
            $ctx = $script:PopupContext
            if ($ctx -and $ctx.OnCopyReply) {
                & $ctx.OnCopyReply
            }
        } catch {
            Write-NotifuLog -Level "error" -Message "Popup copy reply action failed: $($_.Exception.Message)"
        }
    })
    $border.Controls.Add($replyButton)

    $speakButton = New-Object System.Windows.Forms.Button
    $speakButton.Text = "Ulang"
    $speakButton.Location = New-Object System.Drawing.Point 288, 154
    $speakButton.Size = New-Object System.Drawing.Size 58, 29
    $speakButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $speakButton.BackColor = [System.Drawing.Color]::White
    $speakButton.ForeColor = [System.Drawing.Color]::FromArgb(31, 72, 67)
    $speakButton.Add_Click({
        try {
            $ctx = $script:PopupContext
            if ($ctx -and $ctx.OnSpeakAgain) {
                & $ctx.OnSpeakAgain
            }
        } catch {
            Write-NotifuLog -Level "error" -Message "Popup speak action failed: $($_.Exception.Message)"
        }
    })
    $border.Controls.Add($speakButton)

    $voiceButton = New-Object System.Windows.Forms.Button
    $voiceButton.Text = "Voice"
    $voiceButton.Location = New-Object System.Drawing.Point 354, 154
    $voiceButton.Size = New-Object System.Drawing.Size 60, 29
    $voiceButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $voiceButton.BackColor = [System.Drawing.Color]::FromArgb(255, 236, 179)
    $voiceButton.ForeColor = [System.Drawing.Color]::FromArgb(76, 56, 18)
    $voiceButton.Add_Click({
        try {
            $ctx = $script:PopupContext
            if ($ctx -and $ctx.OnVoiceCommand) {
                & $ctx.OnVoiceCommand
            }
        } catch {
            Write-NotifuLog -Level "error" -Message "Popup voice command failed: $($_.Exception.Message)"
        }
    })
    $border.Controls.Add($voiceButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "x"
    $closeButton.Location = New-Object System.Drawing.Point ($width - 32), 7
    $closeButton.Size = New-Object System.Drawing.Size 24, 24
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 252)
    $closeButton.ForeColor = [System.Drawing.Color]::FromArgb(86, 99, 109)
    $closeButton.Add_Click({
        try {
            $ctx = $script:PopupContext
            if ($ctx -and $ctx.Form -and -not $ctx.Form.IsDisposed) {
                $ctx.Form.Close()
            }
        } catch {
            Write-NotifuLog -Level "error" -Message "Popup close action failed: $($_.Exception.Message)"
        }
    })
    $border.Controls.Add($closeButton)

    $moveTimer = New-Object System.Windows.Forms.Timer
    $moveTimer.Interval = 24
    $moveTimer.Add_Tick({
        $ctx = $script:PopupContext
        if (-not $ctx -or -not $ctx.Form -or $ctx.Form.IsDisposed) {
            return
        }

        $ctx.Tick = $ctx.Tick + 1
        if ($ctx.Progress -lt 1) {
            $ctx.Progress = [Math]::Min(1, $ctx.Progress + 0.065)
            $ease = 1 - [Math]::Pow(1 - $ctx.Progress, 3)
            $nextX = [int]($ctx.StartX + (($ctx.TargetX - $ctx.StartX) * $ease))
            $ctx.Form.Location = New-Object System.Drawing.Point $nextX, $ctx.TargetY
            $ctx.Form.Opacity = [Math]::Min(0.98, $ease)
        } else {
            $floatY = [int](7 * [Math]::Sin($ctx.Tick / 9.0))
            $driftX = [int](-10 + (6 * [Math]::Sin($ctx.Tick / 17.0)))
            $ctx.Form.Location = New-Object System.Drawing.Point ($ctx.TargetX + $driftX), ($ctx.TargetY + $floatY)
            $ctx.Form.Opacity = 0.98
        }

        if ($ctx.TypeIndex -lt $ctx.FullMessage.Length) {
            $ctx.TypeIndex = [Math]::Min($ctx.FullMessage.Length, $ctx.TypeIndex + 2)
            $ctx.MessageLabel.Text = $ctx.FullMessage.Substring(0, $ctx.TypeIndex)
        }

        if ($ctx.Avatar -and $ctx.Avatar.Tag) {
            if ($ctx.TypeIndex -lt $ctx.FullMessage.Length -and $ctx.Avatar.Tag.Talk) {
                $ctx.Avatar.Tag.Current = if (($ctx.Tick % 8) -lt 4) { "talk" } else { "base" }
            } else {
                $ctx.Avatar.Tag.Current = "base"
            }
            $ctx.Avatar.Invalidate()
        }

        $offsetY = [int](5 * [Math]::Sin($ctx.Tick / 5.0))
        $offsetX = [int](2 * [Math]::Sin($ctx.Tick / 8.0))
        $ctx.Avatar.Location = New-Object System.Drawing.Point ($ctx.AvatarBaseX + $offsetX), ($ctx.AvatarBaseY + $offsetY)
    })

    $lifeTimer = New-Object System.Windows.Forms.Timer
    $lifeTimer.Interval = [Math]::Max(5, [int]$Settings.ui.popupDurationSeconds) * 1000
    $lifeTimer.Add_Tick({
        param($sender, $eventArgs)
        $sender.Stop()
        $ctx = $script:PopupContext
        if ($ctx -and $ctx.Form -and -not $ctx.Form.IsDisposed) {
            $ctx.Form.Close()
        }
    })

    $form.Add_FormClosed({
        $ctx = $script:PopupContext
        if ($ctx) {
            if ($ctx.MoveTimer) { $ctx.MoveTimer.Stop() }
            if ($ctx.LifeTimer) { $ctx.LifeTimer.Stop() }
            if ($ctx.Avatar -and $ctx.Avatar.Tag) {
                if ($ctx.Avatar.Tag.Base) { $ctx.Avatar.Tag.Base.Dispose() }
                if ($ctx.Avatar.Tag.Talk -and -not [object]::ReferenceEquals($ctx.Avatar.Tag.Base, $ctx.Avatar.Tag.Talk)) { $ctx.Avatar.Tag.Talk.Dispose() }
                $ctx.Avatar.Tag = $null
            }
        }
        $script:PopupContext = $null
    })

    $script:PopupContext = [pscustomobject]@{
        Form = $form
        Avatar = $avatar
        MessageLabel = $message
        MoveTimer = $moveTimer
        LifeTimer = $lifeTimer
        TargetX = $targetX
        TargetY = $targetY
        StartX = $startX
        AvatarBaseX = 14
        AvatarBaseY = 54
        Tick = 0
        Progress = 0.0
        TypeIndex = 0
        FullMessage = [string]$Analysis.announcement
        OnOpenApp = $OnOpenApp
        OnCopyReply = $OnCopyReply
        OnSpeakAgain = $OnSpeakAgain
        OnVoiceCommand = $OnVoiceCommand
    }

    $form.Add_Shown({
        $ctx = $script:PopupContext
        if ($ctx) {
            $ctx.Tick = 0
            $ctx.MoveTimer.Start()
            $ctx.LifeTimer.Start()
        }
    })
    $script:ActivePopup = $form
    if (-not $NoShow) {
        $form.Show()
    }
    return $form
}

function Set-NotifuDesktopPetBubble {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$Expression = "happy",

        [Parameter(Mandatory = $true)]
        $Settings
    )

    if (-not $script:PetContext -or -not $script:PetContext.Form -or $script:PetContext.Form.IsDisposed) {
        return
    }

    if ($Settings.ui.PSObject.Properties["petBubbleEnabled"] -and -not [bool]$Settings.ui.petBubbleEnabled) {
        return
    }

    $ctx = $script:PetContext
    if (-not $ctx.Bubble -or -not $ctx.MessageLabel) {
        return
    }

    $path = Get-NotifuExpressionAssetPath -Settings $Settings -Expression $Expression
    if (Test-Path -LiteralPath $path) {
        if ($ctx.Avatar.Tag) {
            try { $ctx.Avatar.Tag.Dispose() } catch {}
        }
        $ctx.Avatar.Tag = Get-NotifuImage -Path $path
        $ctx.Avatar.Invalidate()
    }

    $ctx.FullText = $Text
    $ctx.TypeIndex = 0
    $ctx.MessageLabel.Text = ""
    $ctx.Bubble.Visible = $true
    $ctx.BubbleTicks = 0
}

function Set-NotifuDesktopPetVisible {
    param([bool]$Visible)

    if ($script:PetContext -and $script:PetContext.Form -and -not $script:PetContext.Form.IsDisposed) {
        $script:PetContext.Form.Visible = $Visible
    }
}

function Show-NotifuDesktopPet {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,

        [scriptblock]$OnClick
    )

    if ($script:PetContext -and $script:PetContext.Form -and -not $script:PetContext.Form.IsDisposed) {
        return $script:PetContext.Form
    }

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $petSize = [int](Get-NotifuProperty -Object $Settings.ui -Name "petSize" -Default 64)
    $width = $petSize + 18
    $height = $petSize + 18
    $transparent = [System.Drawing.Color]::Magenta

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Notifu Pet"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.Size = New-Object System.Drawing.Size $width, $height
    $form.BackColor = $transparent
    $form.TransparencyKey = $transparent
    $form.Location = New-Object System.Drawing.Point ($screen.Right - $width - 30), ($screen.Bottom - $height - 6)

    $avatar = New-Object System.Windows.Forms.PictureBox
    $avatar.Size = New-Object System.Drawing.Size $petSize, $petSize
    $avatar.Location = New-Object System.Drawing.Point 9, 9
    $avatar.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
    $avatar.BackColor = $transparent
    $avatarPath = [string](Get-NotifuProperty -Object $Settings.ui -Name "petImagePath" -Default "")
    if (-not $avatarPath) {
        $avatarPath = Get-NotifuExpressionAssetPath -Settings $Settings -Expression "happy"
    } else {
        $avatarPath = Resolve-NotifuPath -Path $avatarPath
    }

    if (Test-Path -LiteralPath $avatarPath) {
        $avatar.Tag = Get-NotifuImage -Path $avatarPath
    }
    $avatar.Add_Paint({
        param($sender, $eventArgs)
        $image = $sender.Tag
        if ($image) {
            $graphics = $eventArgs.Graphics
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $scale = [Math]::Min($sender.Width / $image.Width, $sender.Height / $image.Height)
            $drawWidth = [int]($image.Width * $scale)
            $drawHeight = [int]($image.Height * $scale)
            $drawX = [int](($sender.Width - $drawWidth) / 2)
            $drawY = [int](($sender.Height - $drawHeight) / 2)
            $graphics.DrawImage($image, (New-Object System.Drawing.Rectangle $drawX, $drawY, $drawWidth, $drawHeight))
        }
    })

    $dragStart = {
        param($sender, $eventArgs)
        $ctx = $script:PetContext
        if ($ctx -and $eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $ctx.Dragging = $true
            $ctx.DragOffset = New-Object System.Drawing.Point $eventArgs.X, $eventArgs.Y
            $ctx.ManualUntil = (Get-Date).AddSeconds(10)
        }
    }

    $dragMove = {
        param($sender, $eventArgs)
        $ctx = $script:PetContext
        if ($ctx -and $ctx.Dragging) {
            $screenPoint = [System.Windows.Forms.Control]::MousePosition
            $ctx.Form.Location = New-Object System.Drawing.Point ($screenPoint.X - $ctx.DragOffset.X), ($screenPoint.Y - $ctx.DragOffset.Y)
        }
    }

    $dragEnd = {
        param($sender, $eventArgs)
        $ctx = $script:PetContext
        if ($ctx) {
            $ctx.Dragging = $false
        }
    }

    $avatar.Add_MouseDown($dragStart)
    $avatar.Add_MouseMove($dragMove)
    $avatar.Add_MouseUp($dragEnd)
    $form.Add_MouseDown($dragStart)
    $form.Add_MouseMove($dragMove)
    $form.Add_MouseUp($dragEnd)
    $form.Controls.Add($avatar)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 45
    $timer.Add_Tick({
        $ctx = $script:PetContext
        if (-not $ctx -or -not $ctx.Form -or $ctx.Form.IsDisposed) {
            return
        }

        if ($ctx.Dragging) {
            return
        }

        $ctx.Tick = $ctx.Tick + 1
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if ($ctx.ManualUntil -and (Get-Date) -lt $ctx.ManualUntil) {
            $safeX = [Math]::Max($bounds.Left + 4, [Math]::Min($ctx.Form.Left, $bounds.Right - $ctx.Form.Width - 4))
            $safeY = [Math]::Max($bounds.Top + 4, [Math]::Min($ctx.Form.Top, $bounds.Bottom - $ctx.Form.Height - 4))
            $ctx.Form.Location = New-Object System.Drawing.Point $safeX, $safeY
            return
        }

        $nextX = $ctx.Form.Left + $ctx.Direction
        if ($nextX -lt ($bounds.Left + 10) -or $nextX -gt ($bounds.Right - $ctx.Form.Width - 10)) {
            $ctx.Direction = -1 * $ctx.Direction
            $nextX = $ctx.Form.Left + $ctx.Direction
        }

        $bob = [int](2 * [Math]::Sin($ctx.Tick / 8.0))
        $ctx.Form.Location = New-Object System.Drawing.Point $nextX, ($bounds.Bottom - $ctx.Form.Height - 6 + $bob)
    })

    $form.Add_FormClosed({
        $ctx = $script:PetContext
        if ($ctx) {
            if ($ctx.Timer) { $ctx.Timer.Stop() }
            if ($ctx.Avatar -and $ctx.Avatar.Tag) {
                try { $ctx.Avatar.Tag.Dispose() } catch {}
                $ctx.Avatar.Tag = $null
            }
        }
        $script:PetContext = $null
    })

    $script:PetContext = [pscustomobject]@{
        Form = $form
        Avatar = $avatar
        Bubble = $null
        MessageLabel = $null
        Timer = $timer
        Direction = -1
        Tick = 0
        FullText = ""
        TypeIndex = 0
        BubbleTicks = 0
        Dragging = $false
        DragOffset = (New-Object System.Drawing.Point 0, 0)
        ManualUntil = $null
        OnClick = $OnClick
    }

    $timer.Start()
    $form.Show()
    return $form
}

function Show-NotifuSettingsWindow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingsPath
    )

    $settings = Get-NotifuSettings -Path $SettingsPath

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Notifu Settings"
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size 650, 560
    $form.MinimumSize = New-Object System.Drawing.Size 650, 560
    $form.Font = New-Object System.Drawing.Font "Segoe UI", 9

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
    $form.Controls.Add($tabs)

    $general = New-Object System.Windows.Forms.TabPage
    $general.Text = "General"
    $tabs.TabPages.Add($general)

    $notifications = New-Object System.Windows.Forms.TabPage
    $notifications.Text = "Notifications"
    $tabs.TabPages.Add($notifications)

    $voice = New-Object System.Windows.Forms.TabPage
    $voice.Text = "Voice"
    $tabs.TabPages.Add($voice)

    $rvc = New-Object System.Windows.Forms.TabPage
    $rvc.Text = "RVC Model"
    $tabs.TabPages.Add($rvc)

    $ai = New-Object System.Windows.Forms.TabPage
    $ai.Text = "AI"
    $tabs.TabPages.Add($ai)

    function Add-Label($parent, $text, $x, $y) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $text
        $label.Location = New-Object System.Drawing.Point $x, $y
        $label.Size = New-Object System.Drawing.Size 160, 24
        $parent.Controls.Add($label)
        return $label
    }

    function Add-TextBox($parent, $text, $x, $y, $w = 360) {
        $box = New-Object System.Windows.Forms.TextBox
        $box.Text = [string]$text
        $box.Location = New-Object System.Drawing.Point $x, $y
        $box.Size = New-Object System.Drawing.Size $w, 24
        $parent.Controls.Add($box)
        return $box
    }

    function Join-SettingList($value) {
        return (@($value) | Where-Object { $_ } | ForEach-Object { [string]$_ }) -join ", "
    }

    function Split-SettingList($text) {
        return @([string]$text -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    function Ensure-SettingProperty($object, $name, $value) {
        if (-not $object.PSObject.Properties[$name]) {
            $object | Add-Member -NotePropertyName $name -NotePropertyValue $value
        }
    }

    [void](Add-Label $general "Nama user" 22 28)
    $userName = Add-TextBox $general $settings.assistant.userName 190 26

    [void](Add-Label $general "Poll seconds" 22 66)
    $poll = New-Object System.Windows.Forms.NumericUpDown
    $poll.Minimum = 1
    $poll.Maximum = 60
    $poll.Value = [decimal]$settings.listener.pollSeconds
    $poll.Location = New-Object System.Drawing.Point 190, 64
    $general.Controls.Add($poll)

    $readBody = New-Object System.Windows.Forms.CheckBox
    $readBody.Text = "Bacakan isi pesan"
    $readBody.Checked = [bool]$settings.privacy.readMessageBody
    $readBody.Location = New-Object System.Drawing.Point 190, 103
    $readBody.Size = New-Object System.Drawing.Size 260, 26
    $general.Controls.Add($readBody)

    $customPopup = New-Object System.Windows.Forms.CheckBox
    $customPopup.Text = "Pakai popup karakter, bukan balloon notification"
    $customPopup.Checked = [bool]$settings.ui.useCustomPopup
    $customPopup.Location = New-Object System.Drawing.Point 190, 137
    $customPopup.Size = New-Object System.Drawing.Size 360, 26
    $general.Controls.Add($customPopup)

    $desktopPet = New-Object System.Windows.Forms.CheckBox
    $desktopPet.Text = "Tampilkan pet kecil di bawah layar"
    $desktopPet.Checked = [bool](Get-NotifuProperty -Object $settings.ui -Name "enableDesktopPet" -Default $true)
    $desktopPet.Location = New-Object System.Drawing.Point 190, 171
    $desktopPet.Size = New-Object System.Drawing.Size 360, 26
    $general.Controls.Add($desktopPet)

    $voiceCommandsEnabled = New-Object System.Windows.Forms.CheckBox
    $voiceCommandsEnabled.Text = "Aktifkan voice command opt-in"
    $voiceCommandsEnabled.Checked = [bool](Get-NotifuProperty -Object (Get-NotifuProperty -Object $settings -Name "voiceCommands" -Default $null) -Name "enabled" -Default $true)
    $voiceCommandsEnabled.Location = New-Object System.Drawing.Point 190, 205
    $voiceCommandsEnabled.Size = New-Object System.Drawing.Size 360, 26
    $general.Controls.Add($voiceCommandsEnabled)

    $startupHint = New-Object System.Windows.Forms.Label
    $startupHint.Text = "Startup/background dikelola oleh scripts\\install-startup.ps1 dan sudah aktif bila install.ps1 berhasil."
    $startupHint.Location = New-Object System.Drawing.Point 22, 250
    $startupHint.Size = New-Object System.Drawing.Size 580, 50
    $general.Controls.Add($startupHint)

    $notificationSettings = Get-NotifuProperty -Object $settings -Name "notifications" -Default $null
    [void](Add-Label $notifications "Mode" 22 28)
    $notificationMode = New-Object System.Windows.Forms.ComboBox
    $notificationMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$notificationMode.Items.Add("all")
    [void]$notificationMode.Items.Add("allowlist")
    $notificationMode.SelectedItem = [string](Get-NotifuProperty -Object $notificationSettings -Name "mode" -Default "all")
    $notificationMode.Location = New-Object System.Drawing.Point 190, 26
    $notificationMode.Size = New-Object System.Drawing.Size 180, 24
    $notifications.Controls.Add($notificationMode)

    [void](Add-Label $notifications "Allow apps" 22 70)
    $allowApps = Add-TextBox $notifications (Join-SettingList (Get-NotifuProperty -Object $notificationSettings -Name "allowAppNameContains" -Default @("WhatsApp", "WhatsApp Desktop"))) 190 68 360

    [void](Add-Label $notifications "Block apps" 22 112)
    $blockApps = Add-TextBox $notifications (Join-SettingList (Get-NotifuProperty -Object $notificationSettings -Name "blockAppNameContains" -Default @("Notifu"))) 190 110 360

    $notificationHelp = New-Object System.Windows.Forms.Label
    $notificationHelp.Text = "Mode all membaca semua toast Windows kecuali block apps. Mode allowlist hanya membaca app yang cocok allow apps. Pisahkan nama dengan koma."
    $notificationHelp.Location = New-Object System.Drawing.Point 22, 158
    $notificationHelp.Size = New-Object System.Drawing.Size 560, 58
    $notifications.Controls.Add($notificationHelp)

    [void](Add-Label $voice "Voice provider" 22 28)
    $provider = New-Object System.Windows.Forms.ComboBox
    $provider.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$provider.Items.Add("local")
    [void]$provider.Items.Add("rvc")
    $provider.SelectedItem = if ([string]$settings.voice.provider -eq "rvc") { "rvc" } else { "local" }
    $provider.Location = New-Object System.Drawing.Point 190, 26
    $provider.Size = New-Object System.Drawing.Size 180, 24
    $voice.Controls.Add($provider)

    [void](Add-Label $voice "Volume" 22 66)
    $volume = New-Object System.Windows.Forms.TrackBar
    $volume.Minimum = 0
    $volume.Maximum = 100
    $volume.Value = [int]$settings.voice.volume
    $volume.Location = New-Object System.Drawing.Point 190, 60
    $volume.Size = New-Object System.Drawing.Size 250, 45
    $voice.Controls.Add($volume)

    [void](Add-Label $voice "Local voice" 22 118)
    $localVoice = New-Object System.Windows.Forms.ComboBox
    $localVoice.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$localVoice.Items.Add("")
    foreach ($v in Get-NotifuInstalledVoices) {
        [void]$localVoice.Items.Add($v.Name)
    }
    $localVoice.SelectedItem = [string]$settings.voice.localVoiceName
    $localVoice.Location = New-Object System.Drawing.Point 190, 116
    $localVoice.Size = New-Object System.Drawing.Size 260, 24
    $voice.Controls.Add($localVoice)

    [void](Add-Label $voice "Voice lama (nonaktif)" 22 158)
    $openAiVoice = Add-TextBox $voice $settings.voice.openAiVoice 190 156 180

    $chime = New-Object System.Windows.Forms.CheckBox
    $chime.Text = "Bunyi chime sebelum bicara"
    $chime.Checked = [bool]$settings.voice.chimeBeforeSpeech
    $chime.Location = New-Object System.Drawing.Point 190, 196
    $chime.Size = New-Object System.Drawing.Size 260, 26
    $voice.Controls.Add($chime)

    [void](Add-Label $rvc "Model .pth" 22 28)
    $modelPath = Add-TextBox $rvc $settings.rvc.modelPath 190 26 390
    [void](Add-Label $rvc "Index .index" 22 66)
    $indexPath = Add-TextBox $rvc $settings.rvc.indexPath 190 64 390
    [void](Add-Label $rvc "Command override" 22 104)
    $rvcCommand = Add-TextBox $rvc $settings.rvc.command 190 102 390

    $commandHelp = New-Object System.Windows.Forms.Label
    $commandHelp.Text = "Kosong = pakai runtime bawaan Notifu. Override mendukung token: {input} {output} {model} {index} {pitch} {textFile}."
    $commandHelp.Location = New-Object System.Drawing.Point 190, 132
    $commandHelp.Size = New-Object System.Drawing.Size 390, 48
    $rvc.Controls.Add($commandHelp)

    [void](Add-Label $rvc "Base voice" 22 188)
    $baseVoice = Add-TextBox $rvc $settings.rvc.baseVoice 190 186 220

    [void](Add-Label $rvc "Pitch" 22 228)
    $pitch = New-Object System.Windows.Forms.NumericUpDown
    $pitch.Minimum = -24
    $pitch.Maximum = 24
    $pitch.Value = [decimal]$settings.rvc.pitch
    $pitch.Location = New-Object System.Drawing.Point 190, 226
    $rvc.Controls.Add($pitch)

    $testRvc = New-Object System.Windows.Forms.Button
    $testRvc.Text = "Test voice"
    $testRvc.Location = New-Object System.Drawing.Point 190, 268
    $testRvc.Size = New-Object System.Drawing.Size 110, 32
    $testRvc.Add_Click({
        $tmp = Get-NotifuSettings -Path $SettingsPath
        $tmp.voice.provider = $provider.SelectedItem
        $tmp.voice.volume = [int]$volume.Value
        $tmp.voice.localVoiceName = [string]$localVoice.SelectedItem
        $tmp.rvc.modelPath = $modelPath.Text
        $tmp.rvc.indexPath = $indexPath.Text
        $tmp.rvc.command = $rvcCommand.Text
        $tmp.rvc.baseVoice = $baseVoice.Text
        $tmp.rvc.pitch = [int]$pitch.Value
        Invoke-NotifuSpeech -Text "Halo Evid, ini suara test Notifu." -Settings $tmp -Async
    })
    $rvc.Controls.Add($testRvc)

    $aiEnabled = New-Object System.Windows.Forms.CheckBox
    $aiEnabled.Text = "AI cloud dinonaktifkan: Notifu langsung membacakan pesan"
    $aiEnabled.Checked = $false
    $aiEnabled.Enabled = $false
    $aiEnabled.Location = New-Object System.Drawing.Point 22, 28
    $aiEnabled.Size = New-Object System.Drawing.Size 360, 26
    $ai.Controls.Add($aiEnabled)

    [void](Add-Label $ai "Model" 22 70)
    $aiModel = Add-TextBox $ai $settings.ai.model 190 68 220

    $aiNote = New-Object System.Windows.Forms.Label
    $aiNote.Text = "Notifu menggunakan template lokal agar popup dan suara tidak menunggu respons jaringan."
    $aiNote.Location = New-Object System.Drawing.Point 22, 112
    $aiNote.Size = New-Object System.Drawing.Size 560, 52
    $ai.Controls.Add($aiNote)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = "Save"
    $save.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $save.Location = New-Object System.Drawing.Point 426, 478
    $save.Size = New-Object System.Drawing.Size 88, 34
    $form.Controls.Add($save)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $cancel.Location = New-Object System.Drawing.Point 522, 478
    $cancel.Size = New-Object System.Drawing.Size 88, 34
    $cancel.Add_Click({ $form.Close() })
    $form.Controls.Add($cancel)

    $shutdown = New-Object System.Windows.Forms.Button
    $shutdown.Text = "Matikan Notifu"
    $shutdown.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $shutdown.Location = New-Object System.Drawing.Point 22, 478
    $shutdown.Size = New-Object System.Drawing.Size 132, 34
    $shutdown.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $shutdown.BackColor = [System.Drawing.Color]::FromArgb(190, 55, 65)
    $shutdown.ForeColor = [System.Drawing.Color]::White
    $shutdown.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Matikan Notifu beserta worker suara yang sedang berjalan?",
            "Matikan Notifu",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        try {
            $root = Split-Path -Parent $PSScriptRoot
            $stopScript = Join-Path $root "scripts\stop.ps1"
            $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            Start-Process `
                -FilePath $powershellPath `
                -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$stopScript`"", "-Silent") `
                -WindowStyle Hidden | Out-Null
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Notifu gagal dimatikan: $($_.Exception.Message)",
                "Notifu",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })
    $form.Controls.Add($shutdown)

    $save.Add_Click({
        Ensure-SettingProperty $settings "notifications" ([pscustomobject]@{})
        Ensure-SettingProperty $settings "voiceCommands" ([pscustomobject]@{})
        Ensure-SettingProperty $settings.notifications "mode" "all"
        Ensure-SettingProperty $settings.notifications "allowAppNameContains" @()
        Ensure-SettingProperty $settings.notifications "blockAppNameContains" @()
        Ensure-SettingProperty $settings.voiceCommands "enabled" $true
        Ensure-SettingProperty $settings.ui "enableDesktopPet" $true

        $settings.assistant.userName = $userName.Text
        $settings.listener.pollSeconds = [int]$poll.Value
        $settings.privacy.readMessageBody = [bool]$readBody.Checked
        $settings.ui.useCustomPopup = [bool]$customPopup.Checked
        $settings.ui.enableDesktopPet = [bool]$desktopPet.Checked
        $settings.notifications.mode = [string]$notificationMode.SelectedItem
        $settings.notifications.allowAppNameContains = @(Split-SettingList $allowApps.Text)
        $settings.notifications.blockAppNameContains = @(Split-SettingList $blockApps.Text)
        $settings.voiceCommands.enabled = [bool]$voiceCommandsEnabled.Checked
        $settings.voice.provider = [string]$provider.SelectedItem
        $settings.voice.volume = [int]$volume.Value
        $settings.voice.localVoiceName = [string]$localVoice.SelectedItem
        $settings.voice.openAiVoice = $openAiVoice.Text
        $settings.voice.chimeBeforeSpeech = [bool]$chime.Checked
        $settings.rvc.modelPath = $modelPath.Text
        $settings.rvc.indexPath = $indexPath.Text
        $settings.rvc.command = $rvcCommand.Text
        $settings.rvc.baseVoice = $baseVoice.Text
        $settings.rvc.pitch = [int]$pitch.Value
        $settings.ai.enabled = $false
        $settings.ai.model = $aiModel.Text
        Save-NotifuSettings -Settings $settings -Path $SettingsPath
        [System.Windows.Forms.MessageBox]::Show("Settings saved. Restart Notifu untuk memastikan semua perubahan aktif.", "Notifu") | Out-Null
        $form.Close()
    })

    [void]$form.ShowDialog()
}

Export-ModuleMember -Function `
    Show-NotifuAssistantPopup, `
    Close-NotifuAssistantPopup, `
    Show-NotifuDesktopPet, `
    Set-NotifuDesktopPetBubble, `
    Set-NotifuDesktopPetVisible, `
    Show-NotifuSettingsWindow, `
    Resolve-NotifuPath
