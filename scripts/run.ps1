param(
    [switch]$Visible
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$nativeCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Notifu\Notifu.exe"),
    (Join-Path $root "dist\app\Notifu.exe")
)
$native = $nativeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($native) {
    Start-Process -FilePath $native -WorkingDirectory (Split-Path -Parent $native)
    return
}

$app = Join-Path $root "src\Notifu.ps1"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

if ($Visible) {
    & $powershell -NoProfile -ExecutionPolicy Bypass -STA -File $app
    return
}

Start-Process `
    -FilePath $powershell `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-WindowStyle", "Hidden", "-File", "`"$app`"", "-Background") `
    -WindowStyle Hidden
