param(
    [switch]$KeepLogs
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

& (Join-Path $root "scripts\stop.ps1") -Silent
& (Join-Path $root "scripts\uninstall-startup.ps1") -Silent

$shortcutTargets = @(
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "Notifu.lnk"),
    (Join-Path ([Environment]::GetFolderPath("Programs")) "Notifu.lnk"),
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "Notifu Settings.lnk"),
    (Join-Path ([Environment]::GetFolderPath("Programs")) "Notifu Settings.lnk")
)

foreach ($shortcutPath in $shortcutTargets) {
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
    }
}

if (-not $KeepLogs) {
    $logDir = Join-Path $root "logs"
    if (Test-Path -LiteralPath $logDir) {
        Remove-Item -LiteralPath $logDir -Recurse -Force
    }
}

Write-Host "Notifu uninstalled."
