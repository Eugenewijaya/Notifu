param(
    [string]$SettingsPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root "src\Notifu.Core.psm1") -Force

if (-not $SettingsPath) {
    $SettingsPath = Join-Path $root "config\notifu.settings.json"
}

$queueDir = Join-Path $root "logs\speech-queue"
if (-not (Test-Path -LiteralPath $queueDir)) {
    New-Item -ItemType Directory -Force -Path $queueDir | Out-Null
}

Write-NotifuLog -Message "Speech queue worker processing."

while ($true) {
    $item = Get-ChildItem -LiteralPath $queueDir -Filter "*.txt" -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Select-Object -First 1

    if (-not $item) {
        break
    }

    try {
        $settings = Get-NotifuSettings -Path $SettingsPath
        $text = (Get-Content -LiteralPath $item.FullName -Raw).Trim()
        Remove-Item -LiteralPath $item.FullName -Force
        if ($text) {
            Invoke-NotifuSpeech -Text $text -Settings $settings
        }
    } catch {
        Write-NotifuLog -Level "error" -Message "Speech queue item failed: $($_.Exception.Message)"
        try { Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue } catch {}
    }
}

Write-NotifuLog -Message "Speech queue worker finished."
