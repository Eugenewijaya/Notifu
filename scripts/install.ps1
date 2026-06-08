param(
    [switch]$NoStartup,
    [switch]$NoShortcut
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$runScript = Join-Path $root "scripts\run.ps1"
$settingsScript = Join-Path $root "scripts\settings.ps1"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$iconPath = Join-Path $root "assets\notifu-app-icon.ico"
$iconLocation = if (Test-Path -LiteralPath $iconPath) { $iconPath } else { "$env:SystemRoot\System32\shell32.dll,277" }

if (-not $NoShortcut) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcutTargets = @(
        @{ Path = (Join-Path ([Environment]::GetFolderPath("Desktop")) "Notifu.lnk"); Script = $runScript; Description = "Notifu AI notification assistant" },
        @{ Path = (Join-Path ([Environment]::GetFolderPath("Programs")) "Notifu.lnk"); Script = $runScript; Description = "Notifu AI notification assistant" },
        @{ Path = (Join-Path ([Environment]::GetFolderPath("Desktop")) "Notifu Settings.lnk"); Script = $settingsScript; Description = "Notifu settings" },
        @{ Path = (Join-Path ([Environment]::GetFolderPath("Programs")) "Notifu Settings.lnk"); Script = $settingsScript; Description = "Notifu settings" }
    )

    foreach ($target in $shortcutTargets) {
        $shortcutPath = $target.Path
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($target.Script)`""
        $shortcut.WorkingDirectory = $root
        $shortcut.IconLocation = $iconLocation
        $shortcut.Description = $target.Description
        $shortcut.Save()
    }
}

if (-not $NoStartup) {
    & (Join-Path $root "scripts\install-startup.ps1") -Silent
}

Write-Host "Notifu installed."
Write-Host "Run now: powershell -ExecutionPolicy Bypass -File `"$runScript`""
if (-not $NoStartup) {
    Write-Host "Startup/background: enabled for current Windows user."
}
