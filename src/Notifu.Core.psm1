Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Speech

function Import-NotifuEnv {
    param(
        [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) ".env.local")
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            return
        }

        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) {
            return
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($name) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Get-NotifuSettings {
    param(
        [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\notifu.settings.json")
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Settings file not found: $Path"
    }

    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return $settings
}

function Save-NotifuSettings {
    param(
        [Parameter(Mandatory = $true)]
        $Settings,

        [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\notifu.settings.json")
    )

    $Settings | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-NotifuObjectValue {
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

function Resolve-NotifuWorkspacePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path (Split-Path -Parent $PSScriptRoot) $Path)
}

function ConvertTo-NotifuProcessArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    $escaped = $Value.Replace('"', '\"')
    if ($escaped -match '\s|["]') {
        return ('"{0}"' -f $escaped)
    }

    return $escaped
}

function Invoke-WinRtAsync {
    param(
        [Parameter(Mandatory = $true)]
        $Operation,

        [Parameter(Mandatory = $true)]
        [type]$ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "AsTask" -and
            $_.IsGenericMethodDefinition -and
            $_.GetGenericArguments().Length -eq 1 -and
            $_.GetParameters().Length -eq 1 -and
            $_.ReturnType.Name -eq 'Task`1'
        } |
        Select-Object -First 1

    if (-not $method) {
        throw "Unable to locate Windows Runtime async bridge."
    }

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    return $task.GetAwaiter().GetResult()
}

function Request-NotifuNotificationAccess {
    $listenerType = [Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $accessType = [Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus, Windows.UI.Notifications, ContentType = WindowsRuntime]

    $listener = $listenerType::Current
    $status = $listener.GetAccessStatus()
    if ($status -eq $accessType::Allowed) {
        return $status.ToString()
    }

    $op = $listener.RequestAccessAsync()
    return (Invoke-WinRtAsync -Operation $op -ResultType $accessType).ToString()
}

function Get-NotifuNotificationAccess {
    $listenerType = [Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
    return $listenerType::Current.GetAccessStatus().ToString()
}

function Get-NotifuRawNotifications {
    $listenerType = [Windows.UI.Notifications.Management.UserNotificationListener, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $kindType = [Windows.UI.Notifications.NotificationKinds, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $notificationType = [Windows.UI.Notifications.UserNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $listType = [System.Collections.Generic.IReadOnlyList``1].MakeGenericType($notificationType)

    $listener = $listenerType::Current
    $op = $listener.GetNotificationsAsync($kindType::Toast)
    return @(Invoke-WinRtAsync -Operation $op -ResultType $listType)
}

function Get-NotifuNotificationText {
    param(
        [Parameter(Mandatory = $true)]
        $UserNotification
    )

    $bindingType = [Windows.UI.Notifications.KnownNotificationBindings, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $binding = $UserNotification.Notification.Visual.GetBinding($bindingType::ToastGeneric)
    if (-not $binding) {
        return @()
    }

    return @($binding.GetTextElements() | ForEach-Object { $_.Text } | Where-Object { $_ })
}

function ConvertTo-NotifuNotification {
    param(
        [Parameter(Mandatory = $true)]
        $UserNotification
    )

    $texts = Get-NotifuNotificationText -UserNotification $UserNotification
    $appName = $UserNotification.AppInfo.DisplayInfo.DisplayName
    $appId = ""
    try {
        $appId = [string]$UserNotification.AppInfo.AppUserModelId
    } catch {
        $appId = ""
    }

    $title = if ($texts.Count -ge 1) { $texts[0] } else { "" }
    $body = if ($texts.Count -ge 2) { ($texts[1..($texts.Count - 1)] -join " ") } else { "" }

    [pscustomobject]@{
        Id = [int]$UserNotification.Id
        AppName = [string]$appName
        AppId = [string]$appId
        Title = [string]$title
        Body = [string]$body
        Text = [string]($texts -join " | ")
        CreatedAt = $UserNotification.CreationTime.ToString("o")
        UniqueKey = "{0}:{1}:{2}" -f $appName.Trim().ToLowerInvariant(), $title.Trim().ToLowerInvariant(), $body.Trim().ToLowerInvariant()
    }
}

function Test-NotifuTrackedNotification {
    param(
        [Parameter(Mandatory = $true)]
        $Notification,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $appName = [string]$Notification.AppName
    if (-not $appName) {
        return $false
    }

    $notificationSettings = Get-NotifuObjectValue -Object $Settings -Name "notifications" -Default $null
    $mode = [string](Get-NotifuObjectValue -Object $notificationSettings -Name "mode" -Default "allowlist")
    $blockList = @(Get-NotifuObjectValue -Object $notificationSettings -Name "blockAppNameContains" -Default @())
    $allowList = @(Get-NotifuObjectValue -Object $notificationSettings -Name "allowAppNameContains" -Default @())

    if (-not $allowList -or $allowList.Count -eq 0) {
        $legacyWhatsApp = Get-NotifuObjectValue -Object $Settings -Name "whatsapp" -Default $null
        $allowList = @(Get-NotifuObjectValue -Object $legacyWhatsApp -Name "appNameContains" -Default @("WhatsApp", "WhatsApp Desktop"))
    }

    foreach ($candidate in $blockList) {
        if ($candidate -and $appName -like "*$candidate*") {
            return $false
        }
    }

    if ($mode -eq "all") {
        return $true
    }

    foreach ($candidate in $allowList) {
        if ($candidate -and $appName -like "*$candidate*") {
            return $true
        }
    }

    return $false
}

function Test-NotifuWhatsAppNotification {
    param(
        [Parameter(Mandatory = $true)]
        $Notification,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    return Test-NotifuTrackedNotification -Notification $Notification -Settings $Settings
}

function Get-NotifuSender {
    param(
        [Parameter(Mandatory = $true)]
        $Notification
    )

    $title = ([string]$Notification.Title).Trim()
    if (-not $title) {
        $appName = ([string]$Notification.AppName).Trim()
        if ($appName) {
            return $appName
        }

        return "notifikasi"
    }

    if ($title -match "^(?<sender>.+?)\s+\(.+\)$") {
        return $Matches.sender.Trim()
    }

    return $title
}

function Get-NotifuLocalAnalysis {
    param(
        [Parameter(Mandatory = $true)]
        $Notification,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $sender = Get-NotifuSender -Notification $Notification
    $appName = ([string]$Notification.AppName).Trim()
    $message = ([string]$Notification.Body).Trim()
    if (-not $message) {
        $message = ([string]$Notification.Text).Trim()
    }

    $urgency = "normal"
    $category = "message"
    $shouldAskReply = $false
    $actionHint = "read_only"

    $lower = $message.ToLowerInvariant()
    if ($lower -match "\b(urgent|penting|darurat|sekarang|cepat|asap|tolong|butuh)\b") {
        $urgency = "high"
        $actionHint = "open_app"
    }

    if ($message -match "\?") {
        $category = "question"
        $shouldAskReply = $true
        $actionHint = "ask_reply"
    }

    if ($lower -match "\b(jam|besok|hari ini|meeting|rapat|jadwal|deadline|ingatkan|reminder|calendar)\b") {
        $category = "schedule"
        if ($actionHint -eq "read_only") {
            $actionHint = "remind_later"
        }
    }

    if ($lower -match "\b(tolong|kerjakan|cek|review|approve|upload|kirim|bayar|invoice|task)\b") {
        $category = "task"
        if ($actionHint -eq "read_only") {
            $actionHint = "open_app"
        }
    }

    if ($lower -match "\b(otp|kode|password|pin|verifikasi|rekening|transfer|token)\b") {
        $category = "sensitive"
        $urgency = "high"
        $actionHint = "open_app"
    }

    $cleanMessage = if ($Settings.privacy.readMessageBody) { $message } else { "pesannya disembunyikan karena privacy mode aktif" }
    $openers = @(
        "Eh $($Settings.assistant.userName), aku nangkep notifikasi baru.",
        "$($Settings.assistant.userName), ada notifikasi masuk nih.",
        "Aku melayang sebentar ya, ada yang baru masuk.",
        "Notifu di sini. Ada notifikasi yang perlu kamu lihat."
    )

    $senderLines = @(
        "Dari $sender lewat $appName.",
        "Sumbernya $appName, pengirimnya $sender.",
        "$appName bilang dari $sender."
    )

    $bodyLines = if ($Settings.privacy.readMessageBody) {
        @(
            "Katanya: $cleanMessage",
            "Isi pesannya: $cleanMessage",
            "Aku bacain singkat: $cleanMessage"
        )
    } else {
        @("Isi pesannya aku sembunyikan karena privacy mode aktif.")
    }

    $announcement = "{0} {1} {2}" -f ($openers | Get-Random), ($senderLines | Get-Random), ($bodyLines | Get-Random)

    if ($urgency -eq "high") {
        $announcement += " Ini kelihatannya penting, jadi aku agak panik dikit."
    } elseif ($shouldAskReply) {
        $announcement += " Ini seperti pertanyaan, mungkin perlu dibalas."
    }

    $replyDraft = if ($shouldAskReply) {
        "Halo $sender, aku cek dulu ya. Nanti aku kabari."
    } else {
        "Oke, aku terima pesannya."
    }

    [pscustomobject]@{
        appName = $appName
        sender = $sender
        summary = $message
        urgency = $urgency
        category = $category
        announcement = $announcement
        suggestedReply = $replyDraft
        actionHint = $actionHint
        expression = if ($urgency -eq "high" -or $category -eq "sensitive") { "worried" } elseif ($category -eq "question") { "curious" } elseif ($category -eq "schedule" -or $category -eq "task") { "focused" } else { "happy" }
        source = "local"
    }
}

function New-NotifuBaseSpeechWav {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $voice = New-Object -ComObject SAPI.SpVoice
    $voice.Rate = [int]$Settings.voice.localRate
    $voice.Volume = [int]$Settings.voice.volume

    if ($Settings.voice.localVoiceName) {
        foreach ($candidate in @($voice.GetVoices())) {
            if ($candidate.GetDescription() -eq $Settings.voice.localVoiceName) {
                $voice.Voice = $candidate
                break
            }
        }
    } elseif ($Settings.voice.preferFemale) {
        foreach ($candidate in @($voice.GetVoices())) {
            if ($candidate.GetDescription() -like "*Zira*" -or $candidate.GetDescription() -like "*Female*") {
                $voice.Voice = $candidate
                break
            }
        }
    }

    $stream = New-Object -ComObject SAPI.SpFileStream
    $stream.Open($OutputPath, 3, $false)
    $voice.AudioOutputStream = $stream
    [void]$voice.Speak($Text, 0)
    $stream.Close()
}

function Invoke-NotifuRvcSpeech {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        $Settings,

        [switch]$Async
    )

    $rvcSettings = Get-NotifuObjectValue -Object $Settings -Name "rvc" -Default $null
    if (-not $rvcSettings) {
        Write-NotifuLog -Level "warn" -Message "RVC provider selected, but rvc settings are missing. Falling back to local voice."
        return $false
    }

    $modelPath = [string](Get-NotifuObjectValue -Object $rvcSettings -Name "modelPath" -Default "")
    $indexPath = [string](Get-NotifuObjectValue -Object $rvcSettings -Name "indexPath" -Default "")
    $commandOverride = [string](Get-NotifuObjectValue -Object $rvcSettings -Name "command" -Default "")

    if (-not (Test-Path -LiteralPath $modelPath)) {
        Write-NotifuLog -Level "warn" -Message "RVC model not found: $modelPath"
        return $false
    }

    if ($indexPath -and -not (Test-Path -LiteralPath $indexPath)) {
        Write-NotifuLog -Level "warn" -Message "RVC index not found: $indexPath"
        return $false
    }

    $audioDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\audio"
    if (-not (Test-Path -LiteralPath $audioDir)) {
        New-Item -ItemType Directory -Force -Path $audioDir | Out-Null
    }

    $id = [Guid]::NewGuid().ToString("N")
    $baseWav = Join-Path $audioDir "notifu-base-$id.wav"
    $outWav = Join-Path $audioDir "notifu-rvc-$id.wav"
    $textFile = Join-Path $audioDir "notifu-text-$id.txt"
    $stdoutPath = Join-Path $audioDir "notifu-rvc-$id.out.log"
    $stderrPath = Join-Path $audioDir "notifu-rvc-$id.err.log"

    try {
        New-NotifuBaseSpeechWav -Text $Text -OutputPath $baseWav -Settings $Settings
        Set-Content -LiteralPath $textFile -Value $Text -Encoding UTF8

        $timeoutSeconds = [int](Get-NotifuObjectValue -Object $rvcSettings -Name "timeoutSeconds" -Default 240)
        $minOutputBytes = [int](Get-NotifuObjectValue -Object $rvcSettings -Name "minOutputBytes" -Default 2048)

        if ($commandOverride) {
            $expanded = $commandOverride
            $expanded = $expanded.Replace("{input}", $baseWav)
            $expanded = $expanded.Replace("{output}", $outWav)
            $expanded = $expanded.Replace("{model}", $modelPath)
            $expanded = $expanded.Replace("{index}", $indexPath)
            $expanded = $expanded.Replace("{pitch}", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "pitch" -Default 0))
            $expanded = $expanded.Replace("{textFile}", $textFile)

            $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", $expanded) -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        } else {
            $pythonPath = Resolve-NotifuWorkspacePath -Path ([string](Get-NotifuObjectValue -Object $rvcSettings -Name "pythonPath" -Default ".venv-rvc\Scripts\python.exe"))
            $wrapperScript = Resolve-NotifuWorkspacePath -Path ([string](Get-NotifuObjectValue -Object $rvcSettings -Name "wrapperScript" -Default "scripts\notifu_rvc.py"))

            if (-not (Test-Path -LiteralPath $pythonPath)) {
                throw "RVC Python runtime not found: $pythonPath"
            }

            if (-not (Test-Path -LiteralPath $wrapperScript)) {
                throw "RVC wrapper script not found: $wrapperScript"
            }

            $argumentList = @(
                $wrapperScript,
                "--text-file", $textFile,
                "--fallback-input", $baseWav,
                "--output", $outWav,
                "--model", $modelPath,
                "--index", $indexPath,
                "--pitch", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "pitch" -Default 0),
                "--voice", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "baseVoice" -Default "id-ID-GadisNeural"),
                "--device", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "device" -Default "cpu:0"),
                "--method", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "method" -Default "harvest"),
                "--version", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "version" -Default "v2"),
                "--index-rate", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "indexRate" -Default 0.6),
                "--filter-radius", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "filterRadius" -Default 3),
                "--resample-sr", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "resampleSr" -Default 0),
                "--rms-mix-rate", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "rmsMixRate" -Default 0.25),
                "--protect", [string](Get-NotifuObjectValue -Object $rvcSettings -Name "protect" -Default 0.5),
                "--min-output-bytes", [string]$minOutputBytes
            )
            $argumentString = ($argumentList | ForEach-Object { ConvertTo-NotifuProcessArgument -Value ([string]$_) }) -join " "
            $process = Start-Process -FilePath $pythonPath -ArgumentList $argumentString -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        }

        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            throw "RVC command timed out after $timeoutSeconds seconds."
        }

        [void]$process.WaitForExit()
        $process.Refresh()
        $exitCode = $process.ExitCode
        if ($null -eq $exitCode) {
            $exitCode = 0
        }

        if ($exitCode -ne 0) {
            throw "RVC command exited with code $exitCode."
        }

        if (-not (Test-Path -LiteralPath $outWav)) {
            throw "RVC command did not produce output file: $outWav"
        }

        $outputLength = (Get-Item -LiteralPath $outWav).Length
        if ($outputLength -lt $minOutputBytes) {
            throw "RVC command produced an invalid audio file ($outputLength bytes): $outWav"
        }

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { (Get-Content -LiteralPath $stdoutPath -Raw).Trim() } else { "" }
        if ($stdout) {
            Write-NotifuLog -Message "RVC speech succeeded: $stdout"
        }

        $player = New-Object System.Media.SoundPlayer
        $player.SoundLocation = $outWav
        $player.Load()
        if ($Async) {
            $player.Play()
        } else {
            $player.PlaySync()
        }
        return $true
    } catch {
        $stderr = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Raw).Trim() } else { "" }
        if ($stderr) {
            Write-NotifuLog -Level "warn" -Message "RVC stderr: $stderr"
        }
        Write-NotifuLog -Level "warn" -Message "RVC speech failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-OpenAIKey {
    Import-NotifuEnv
    $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Process")
    if (-not $key) {
        $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "User")
    }
    if (-not $key) {
        $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Machine")
    }
    return $key
}

function Invoke-NotifuOpenAIAnalysis {
    param(
        [Parameter(Mandatory = $true)]
        $Notification,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $apiKey = Get-OpenAIKey
    if (-not $apiKey) {
        return $null
    }

    $sender = Get-NotifuSender -Notification $Notification
    $appName = ([string]$Notification.AppName).Trim()
    $message = ([string]$Notification.Body).Trim()
    if (-not $message) {
        $message = ([string]$Notification.Text).Trim()
    }

    $payload = @{
        model = $Settings.ai.model
        input = @(
            @{
                role = "system"
                content = @(
                    @{
                        type = "input_text"
                        text = "Kamu adalah Notifu, asisten notifikasi pribadi berbahasa Indonesia. Jawab hanya JSON valid. Jangan meniru karakter, voice actor, orang nyata, atau IP tertentu. Gaya bicara boleh playful, sedikit centil, agak ceroboh, hangat, anime-inspired original, dan adaptif terhadap bahasa manusia. Jangan mengarang isi notifikasi yang tidak ada."
                    }
                )
            },
            @{
                role = "user"
                content = @(
                    @{
                        type = "input_text"
                        text = @"
Analisis notifikasi Windows ini.
Nama user: $($Settings.assistant.userName)
Nama aplikasi: $appName
Judul/pengirim: $sender
Isi pesan: $message
Privacy read body aktif: $($Settings.privacy.readMessageBody)

Kembalikan JSON dengan field:
appName, sender, summary, urgency low|normal|high, category message|question|schedule|task|sensitive|unknown, announcement, suggestedReply, actionHint read_only|ask_reply|open_app|remind_later, expression happy|talking|curious|focused|worried|sleepy.
Announcement harus singkat, natural, Bahasa Indonesia santai, maksimal 2 kalimat, dan terasa seperti karakter asisten original yang hidup.
SuggestedReply harus sopan, pendek, dan tidak mengirim info sensitif.
"@
                    }
                )
            }
        )
        text = @{
            format = @{
                type = "json_schema"
                name = "notifu_notification_analysis"
                strict = $true
                schema = @{
                    type = "object"
                    additionalProperties = $false
                    properties = @{
                        appName = @{ type = "string" }
                        sender = @{ type = "string" }
                        summary = @{ type = "string" }
                        urgency = @{ type = "string"; enum = @("low", "normal", "high") }
                        category = @{ type = "string"; enum = @("message", "question", "schedule", "task", "sensitive", "unknown") }
                        announcement = @{ type = "string" }
                        suggestedReply = @{ type = "string" }
                        actionHint = @{ type = "string"; enum = @("read_only", "ask_reply", "open_app", "remind_later") }
                        expression = @{ type = "string"; enum = @("happy", "talking", "curious", "focused", "worried", "sleepy") }
                    }
                    required = @("appName", "sender", "summary", "urgency", "category", "announcement", "suggestedReply", "actionHint", "expression")
                }
            }
        }
    }

    $headers = @{
        Authorization = "Bearer $apiKey"
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.openai.com/v1/responses" `
            -Method Post `
            -Headers $headers `
            -Body ($payload | ConvertTo-Json -Depth 20) `
            -TimeoutSec $Settings.ai.timeoutSeconds

        $jsonText = $null
        if ($response.output_text) {
            $jsonText = [string]$response.output_text
        } elseif ($response.output) {
            foreach ($item in $response.output) {
                if ($item.content) {
                    foreach ($content in $item.content) {
                        if ($content.text) {
                            $jsonText = [string]$content.text
                            break
                        }
                    }
                }
                if ($jsonText) {
                    break
                }
            }
        }

        if (-not $jsonText) {
            throw "OpenAI response did not contain output text."
        }

        $analysis = $jsonText | ConvertFrom-Json
        $analysis | Add-Member -NotePropertyName source -NotePropertyValue "openai" -Force
        return $analysis
    } catch {
        Write-NotifuLog -Level "warn" -Message "OpenAI analysis failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-NotifuAnalysis {
    param(
        [Parameter(Mandatory = $true)]
        $Notification,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    if ($Settings.ai.enabled) {
        $cloud = Invoke-NotifuOpenAIAnalysis -Notification $Notification -Settings $Settings
        if ($cloud) {
            return $cloud
        }
    }

    return Get-NotifuLocalAnalysis -Notification $Notification -Settings $Settings
}

function Get-NotifuOpenAIOutputText {
    param($Response)

    if ($Response.output_text) {
        return [string]$Response.output_text
    }

    if ($Response.output) {
        foreach ($item in $Response.output) {
            if ($item.content) {
                foreach ($content in $item.content) {
                    if ($content.text) {
                        return [string]$content.text
                    }
                }
            }
        }
    }

    return ""
}

function Invoke-NotifuOpenAIConversation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        $Notification,

        $Analysis,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $apiKey = Get-OpenAIKey
    if (-not $apiKey) {
        return $null
    }

    $appName = if ($Analysis -and $Analysis.appName) { [string]$Analysis.appName } elseif ($Notification) { [string]$Notification.AppName } else { "" }
    $sender = if ($Analysis -and $Analysis.sender) { [string]$Analysis.sender } elseif ($Notification) { Get-NotifuSender -Notification $Notification } else { "" }
    $summary = if ($Analysis -and $Analysis.summary) { [string]$Analysis.summary } elseif ($Notification) { [string]$Notification.Text } else { "" }
    $suggestedReply = if ($Analysis -and $Analysis.suggestedReply) { [string]$Analysis.suggestedReply } else { "" }

    $payload = @{
        model = $Settings.ai.model
        input = @(
            @{
                role = "system"
                content = @(
                    @{
                        type = "input_text"
                        text = "Kamu adalah Notifu, asisten notifikasi Windows berbahasa Indonesia. Bicara natural, singkat, playful, sedikit centil, agak ceroboh, dan anime-inspired original. Jangan meniru karakter, voice actor, orang nyata, atau IP tertentu. Jangan klaim menjalankan aksi yang tidak diberi tahu sistem."
                    }
                )
            },
            @{
                role = "user"
                content = @(
                    @{
                        type = "input_text"
                        text = @"
Nama user: $($Settings.assistant.userName)
Aplikasi notifikasi: $appName
Pengirim/judul: $sender
Ringkasan notifikasi: $summary
Draft balasan saat ini: $suggestedReply
Perintah atau ucapan user: $CommandText

Balas dalam Bahasa Indonesia, maksimal 2 kalimat. Kalau user minta balasan, buat draft yang aman dan singkat. Jangan mengirim pesan otomatis.
"@
                    }
                )
            }
        )
    }

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.openai.com/v1/responses" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $apiKey"; "Content-Type" = "application/json" } `
            -Body ($payload | ConvertTo-Json -Depth 12) `
            -TimeoutSec $Settings.ai.timeoutSeconds

        return (Get-NotifuOpenAIOutputText -Response $response).Trim()
    } catch {
        Write-NotifuLog -Level "warn" -Message "OpenAI conversation failed: $($_.Exception.Message)"
        return $null
    }
}

function Read-NotifuVoiceCommand {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $voiceCommandSettings = Get-NotifuObjectValue -Object $Settings -Name "voiceCommands" -Default $null
    if ($voiceCommandSettings -and -not [bool](Get-NotifuObjectValue -Object $voiceCommandSettings -Name "enabled" -Default $true)) {
        return [pscustomobject]@{
            Text = ""
            Confidence = 0
            Status = "disabled"
            Error = "Voice command disabled in settings."
        }
    }

    try {
        Add-Type -AssemblyName System.Speech
        $timeoutSeconds = [int](Get-NotifuObjectValue -Object $voiceCommandSettings -Name "listenTimeoutSeconds" -Default 6)
        $cultureName = [string](Get-NotifuObjectValue -Object $voiceCommandSettings -Name "culture" -Default "")
        $recognizer = $null

        try {
            if ($cultureName) {
                $culture = [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
                $recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine $culture
            }
        } catch {
            $recognizer = $null
        }

        if (-not $recognizer) {
            $recognizer = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        }

        $recognizer.SetInputToDefaultAudioDevice()
        $dictation = New-Object System.Speech.Recognition.DictationGrammar
        $recognizer.LoadGrammar($dictation)
        Write-NotifuLog -Message "Voice command listening for up to $timeoutSeconds seconds."
        $result = $recognizer.Recognize([TimeSpan]::FromSeconds($timeoutSeconds))

        if (-not $result) {
            return [pscustomobject]@{
                Text = ""
                Confidence = 0
                Status = "timeout"
                Error = ""
            }
        }

        return [pscustomobject]@{
            Text = [string]$result.Text
            Confidence = [double]$result.Confidence
            Status = "ok"
            Error = ""
        }
    } catch {
        Write-NotifuLog -Level "warn" -Message "Voice command failed: $($_.Exception.Message)"
        return [pscustomobject]@{
            Text = ""
            Confidence = 0
            Status = "error"
            Error = $_.Exception.Message
        }
    } finally {
        if ($recognizer) {
            try { $recognizer.Dispose() } catch {}
        }
    }
}

function Get-NotifuVoiceCommandAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        $Notification,

        $Analysis,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $text = $CommandText.Trim()
    $lower = $text.ToLowerInvariant()
    $userName = [string]$Settings.assistant.userName
    $voiceCommandSettings = Get-NotifuObjectValue -Object $Settings -Name "voiceCommands" -Default $null
    $wakePhrase = ([string](Get-NotifuObjectValue -Object $voiceCommandSettings -Name "wakePhrase" -Default "halo notifu")).ToLowerInvariant()

    if (-not $text) {
        return [pscustomobject]@{
            Action = "none"
            Response = "Aku belum dengar apa-apa. Coba ulangi pelan-pelan ya."
            DraftReply = ""
        }
    }

    if ($wakePhrase -and $lower -notmatch [Regex]::Escape($wakePhrase)) {
        return [pscustomobject]@{
            Action = "none"
            Response = "Panggil aku dengan '$wakePhrase' dulu ya, biar aku tahu kamu lagi ngomong ke Notifu."
            DraftReply = ""
        }
    }

    if ($wakePhrase) {
        $lower = ($lower -replace [Regex]::Escape($wakePhrase), "").Trim()
        $text = ($text -replace [Regex]::Escape($wakePhrase), "").Trim()
    }

    if (-not $lower) {
        return [pscustomobject]@{
            Action = "wake"
            Response = "Iya, Notifu di sini. Mau aku ulangi, hide, off, on, status, atau buka aplikasi sumber?"
            DraftReply = ""
        }
    }

    if ($lower -match "\b(status|cek status)\b") {
        return [pscustomobject]@{
            Action = "status"
            Response = "Statusku aktif. Voice pakai RVC queue satu-satu, dan pet kecilku cuma jalan-jalan sambil bisa kamu drag."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(hide|sembunyi|umpet)\b") {
        return [pscustomobject]@{
            Action = "hide_pet"
            Response = "Oke, pet kecilku aku sembunyikan dulu."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(show|muncul|tampil)\b") {
        return [pscustomobject]@{
            Action = "show_pet"
            Response = "Aku munculkan pet kecilnya lagi."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(off|mati|nonaktif)\b") {
        return [pscustomobject]@{
            Action = "voice_off"
            Response = "Oke, suara Notifu aku matikan dulu. Notifikasi tetap jalan tanpa suara."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(on|nyala|aktifkan suara|voice on)\b") {
        return [pscustomobject]@{
            Action = "voice_on"
            Response = "Suara Notifu aktif lagi. Aku jawab satu-satu biar enggak tumpang tindih."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(buka|open)\b") {
        return [pscustomobject]@{
            Action = "open_app"
            Response = "Oke $userName, aku coba buka aplikasi sumbernya."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(ulang|ulangi|repeat|bacakan lagi)\b") {
        return [pscustomobject]@{
            Action = "repeat"
            Response = if ($Analysis -and $Analysis.announcement) { [string]$Analysis.announcement } else { "Belum ada notifikasi terakhir untuk kuulangi." }
            DraftReply = ""
        }
    }

    if ($lower -match "\b(copy|salin|clipboard)\b") {
        return [pscustomobject]@{
            Action = "copy_reply"
            Response = "Siap, draft balasannya aku salin ke clipboard."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(abaikan|dismiss|tutup|diam)\b") {
        return [pscustomobject]@{
            Action = "dismiss"
            Response = "Aku tutup bubble-nya dulu. Kalau ada yang penting, aku muncul lagi."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(pause|jeda|berhenti dulu)\b") {
        return [pscustomobject]@{
            Action = "pause"
            Response = "Notifu aku pause dulu. Aku enggak bakal bacain notifikasi sampai kamu resume."
            DraftReply = ""
        }
    }

    if ($lower -match "\b(resume|lanjut|aktif lagi)\b") {
        return [pscustomobject]@{
            Action = "resume"
            Response = "Aku aktif lagi. Jangan kaget kalau aku melayang masuk, ya."
            DraftReply = ""
        }
    }

    $cloudReply = $null
    if ($Settings.ai.enabled) {
        $cloudReply = Invoke-NotifuOpenAIConversation -CommandText $text -Notification $Notification -Analysis $Analysis -Settings $Settings
    }

    if ($cloudReply) {
        return [pscustomobject]@{
            Action = "chat"
            Response = $cloudReply
            DraftReply = ""
        }
    }

    return [pscustomobject]@{
        Action = "chat"
        Response = "Aku dengar: $text. Tapi tanpa AI key, aku baru paham perintah dasar seperti hide, show, off, on, status, buka, ulangi, salin, abaikan, pause, dan resume."
        DraftReply = ""
    }
}

function Invoke-NotifuOpenAITts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        $Settings
    )

    $apiKey = Get-OpenAIKey
    if (-not $apiKey) {
        return $false
    }

    $audioDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\audio"
    if (-not (Test-Path -LiteralPath $audioDir)) {
        New-Item -ItemType Directory -Force -Path $audioDir | Out-Null
    }

    $audioPath = Join-Path $audioDir ("notifu-{0}.wav" -f ([Guid]::NewGuid().ToString("N")))
    $payload = @{
        model = $Settings.voice.openAiTtsModel
        voice = $Settings.voice.openAiVoice
        input = $Text
        instructions = $Settings.voice.openAiInstructions
        response_format = "wav"
    }

    try {
        Invoke-WebRequest `
            -Uri "https://api.openai.com/v1/audio/speech" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $apiKey"; "Content-Type" = "application/json" } `
            -Body ($payload | ConvertTo-Json -Depth 8) `
            -OutFile $audioPath `
            -TimeoutSec $Settings.ai.timeoutSeconds | Out-Null

        $player = New-Object System.Media.SoundPlayer
        $player.SoundLocation = $audioPath
        $player.Load()
        $player.PlaySync()
        return $true
    } catch {
        Write-NotifuLog -Level "warn" -Message "OpenAI TTS failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-NotifuSpeechQueuePath {
    $queueDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\speech-queue"
    if (-not (Test-Path -LiteralPath $queueDir)) {
        New-Item -ItemType Directory -Force -Path $queueDir | Out-Null
    }

    return $queueDir
}

function Test-NotifuSpeechQueueWorkerRunning {
    try {
        $root = [Regex]::Escape((Split-Path -Parent $PSScriptRoot))
        $pattern = "$root.*scripts\\process-speech-queue\.ps1"
        $currentPid = $PID
        $workers = @(Get-CimInstance Win32_Process |
            Where-Object { $_.ProcessId -ne $currentPid -and $_.CommandLine -match $pattern })
        return ($workers.Count -gt 0)
    } catch {
        Write-NotifuLog -Level "warn" -Message "Unable to inspect speech queue worker: $($_.Exception.Message)"
        return $false
    }
}

function Start-NotifuSpeechQueueWorker {
    param(
        [string]$SettingsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\notifu.settings.json")
    )

    if (Test-NotifuSpeechQueueWorkerRunning) {
        return
    }

    $root = Split-Path -Parent $PSScriptRoot
    $workerScript = Join-Path $root "scripts\process-speech-queue.ps1"
    if (-not (Test-Path -LiteralPath $workerScript)) {
        Write-NotifuLog -Level "warn" -Message "Speech queue worker not found: $workerScript"
        return
    }

    $powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $workerArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $workerScript,
        "-SettingsPath", $SettingsPath
    )
    $workerArgumentString = ($workerArgs | ForEach-Object { ConvertTo-NotifuProcessArgument -Value ([string]$_) }) -join " "
    Start-Process -FilePath $powershellPath -ArgumentList $workerArgumentString -WindowStyle Hidden | Out-Null
    Write-NotifuLog -Message "Speech queue worker started."
}

function Add-NotifuSpeechQueueItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$SettingsPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "config\notifu.settings.json")
    )

    $queueDir = Get-NotifuSpeechQueuePath
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
    $queuePath = Join-Path $queueDir ("{0}-{1}.txt" -f $stamp, [Guid]::NewGuid().ToString("N"))
    Set-Content -LiteralPath $queuePath -Value $Text -Encoding UTF8
    Start-NotifuSpeechQueueWorker -SettingsPath $SettingsPath
    Write-NotifuLog -Message "Speech queued: $queuePath"
}

function Invoke-NotifuSpeech {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        $Settings
        ,

        [switch]$Async
    )

    if (-not $Settings.voice.enabled) {
        return
    }

    if ($Async) {
        Add-NotifuSpeechQueueItem -Text $Text
        return
    }

    if ($Settings.voice.provider -eq "openai" -and (Invoke-NotifuOpenAITts -Text $Text -Settings $Settings)) {
        return
    }

    if ($Settings.voice.provider -eq "rvc") {
        if (Invoke-NotifuRvcSpeech -Text $Text -Settings $Settings) {
            return
        }

        $rvcOnly = [bool](Get-NotifuObjectValue -Object $Settings.voice -Name "rvcOnly" -Default $false)
        if ($rvcOnly) {
            Write-NotifuLog -Level "warn" -Message "RVC-only voice is enabled; local fallback suppressed."
            return
        }
    }

    if ($Settings.voice.chimeBeforeSpeech) {
        try {
            [System.Media.SystemSounds]::Exclamation.Play()
            Start-Sleep -Milliseconds 250
        } catch {
            Write-NotifuLog -Level "warn" -Message "Chime failed: $($_.Exception.Message)"
        }
    }

    try {
        $voice = New-Object -ComObject SAPI.SpVoice
        $voice.Rate = [int]$Settings.voice.localRate
        $voice.Volume = [int]$Settings.voice.volume

        if ($Settings.voice.localVoiceName) {
            foreach ($candidate in @($voice.GetVoices())) {
                if ($candidate.GetDescription() -eq $Settings.voice.localVoiceName) {
                    $voice.Voice = $candidate
                    break
                }
            }
        } elseif ($Settings.voice.preferFemale) {
            foreach ($candidate in @($voice.GetVoices())) {
                if ($candidate.GetDescription() -like "*Zira*" -or $candidate.GetDescription() -like "*Female*") {
                    $voice.Voice = $candidate
                    break
                }
            }
        }

        $flags = if ($Async) { 1 } else { 0 }
        [void]$voice.Speak($Text, $flags)
        return
    } catch {
        Write-NotifuLog -Level "warn" -Message "SAPI speech failed: $($_.Exception.Message)"
    }

    try {
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.Rate = [int]$Settings.voice.localRate
        $synth.Volume = [int]$Settings.voice.volume

        if ($Settings.voice.localVoiceName) {
            try {
                $synth.SelectVoice($Settings.voice.localVoiceName)
            } catch {
                Write-NotifuLog -Level "warn" -Message "Local voice not found: $($Settings.voice.localVoiceName)"
            }
        } elseif ($Settings.voice.preferFemale) {
            $femaleVoice = $synth.GetInstalledVoices() |
                Where-Object { $_.VoiceInfo.Gender.ToString() -eq "Female" } |
                Select-Object -First 1
            if ($femaleVoice) {
                $synth.SelectVoice($femaleVoice.VoiceInfo.Name)
            }
        }

        if ($Async) {
            [void]$synth.SpeakAsync($Text)
        } else {
            $synth.Speak($Text)
        }
    } catch {
        Write-NotifuLog -Level "error" -Message "Local speech failed: $($_.Exception.Message)"
    }
}

function Write-NotifuLog {
    param(
        [string]$Level = "info",
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $logDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs"
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }

    $line = "{0} [{1}] {2}" -f (Get-Date).ToString("s"), $Level.ToUpperInvariant(), $Message
    Add-Content -LiteralPath (Join-Path $logDir "notifu.log") -Value $line -Encoding UTF8
}

function Open-NotifuWhatsApp {
    try {
        Start-Process "whatsapp:" | Out-Null
        return $true
    } catch {
        try {
            Start-Process "https://web.whatsapp.com/" | Out-Null
            return $true
        } catch {
            Write-NotifuLog -Level "error" -Message "Unable to open WhatsApp: $($_.Exception.Message)"
            return $false
        }
    }
}

function Open-NotifuNotificationApp {
    param(
        $Notification
    )

    if ($Notification) {
        $appName = [string]$Notification.AppName
        if ($appName -like "*WhatsApp*") {
            return Open-NotifuWhatsApp
        }

        $appId = [string](Get-NotifuObjectValue -Object $Notification -Name "AppId" -Default "")
        if ($appId) {
            try {
                Start-Process ("shell:AppsFolder\{0}" -f $appId) | Out-Null
                return $true
            } catch {
                Write-NotifuLog -Level "warn" -Message "Unable to open source app by AppId ${appId}: $($_.Exception.Message)"
            }
        }

        if ($appName) {
            Write-NotifuLog -Level "warn" -Message "No launch target available for notification app: $appName"
            return $false
        }
    }

    return Open-NotifuWhatsApp
}

function Get-NotifuInstalledVoices {
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    return @($synth.GetInstalledVoices() | ForEach-Object {
        [pscustomobject]@{
            Name = $_.VoiceInfo.Name
            Gender = $_.VoiceInfo.Gender.ToString()
            Culture = $_.VoiceInfo.Culture.Name
        }
    })
}

Export-ModuleMember -Function `
    Import-NotifuEnv, `
    Get-NotifuSettings, `
    Save-NotifuSettings, `
    Request-NotifuNotificationAccess, `
    Get-NotifuNotificationAccess, `
    Get-NotifuRawNotifications, `
    ConvertTo-NotifuNotification, `
    Test-NotifuTrackedNotification, `
    Test-NotifuWhatsAppNotification, `
    Get-NotifuAnalysis, `
    Read-NotifuVoiceCommand, `
    Get-NotifuVoiceCommandAction, `
    Invoke-NotifuSpeech, `
    Write-NotifuLog, `
    Open-NotifuWhatsApp, `
    Open-NotifuNotificationApp, `
    Get-NotifuInstalledVoices
