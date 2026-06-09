$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$nativeCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Notifu\Notifu.exe"),
    (Join-Path $root "dist\app\Notifu.exe")
)
$native = $nativeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($native) {
    Start-Process -FilePath $native -ArgumentList "--settings" -WorkingDirectory (Split-Path -Parent $native)
    return
}

$app = Join-Path $root "src\Notifu.ps1"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

& $powershell -NoProfile -ExecutionPolicy Bypass -STA -File $app -OpenSettings
