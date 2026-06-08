param(
    [switch]$All,
    [switch]$SpeakSample
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root "src\Notifu.Core.psm1") -Force

$settings = Get-NotifuSettings
$access = Request-NotifuNotificationAccess
Write-Host "Notification listener access: $access"

$items = Get-NotifuRawNotifications | ForEach-Object { ConvertTo-NotifuNotification -UserNotification $_ }
$filtered = if ($All) {
    $items
} else {
    $items | Where-Object { Test-NotifuTrackedNotification -Notification $_ -Settings $settings }
}

if (-not $filtered) {
    Write-Host "No matching notification found."
    Write-Host "Tip: trigger any allowed Windows toast notification, then rerun this script."
} else {
    $filtered |
        Select-Object -First 10 Id, AppName, AppId, Title, Body, CreatedAt |
        Format-Table -Wrap -AutoSize
}

if ($SpeakSample) {
    $sample = if ($filtered) {
        $filtered | Select-Object -First 1
    } else {
        [pscustomobject]@{
            Title = "Raka"
            Body = "Besok jadi meeting jam sepuluh?"
            Text = "Raka | Besok jadi meeting jam sepuluh?"
            AppName = "WhatsApp"
        }
    }

    $analysis = Get-NotifuAnalysis -Notification $sample -Settings $settings
    Write-Host "Sample analysis:"
    $analysis | ConvertTo-Json -Depth 8
    Invoke-NotifuSpeech -Text $analysis.announcement -Settings $settings
}
