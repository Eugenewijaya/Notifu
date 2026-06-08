param(
    [Parameter(Mandatory = $true)]
    [string]$TextFile,

    [string]$SettingsPath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root "src\Notifu.Core.psm1") -Force

try {
    if (-not $SettingsPath) {
        $SettingsPath = Join-Path $root "config\notifu.settings.json"
    }

    $settings = Get-NotifuSettings -Path $SettingsPath
    $text = Get-Content -LiteralPath $TextFile -Raw
    Invoke-NotifuSpeech -Text $text -Settings $settings
} catch {
    Write-NotifuLog -Level "error" -Message "Async speech worker failed: $($_.Exception.Message)"
}
