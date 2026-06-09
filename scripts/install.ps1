$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$setup = Join-Path $root "dist\Notifu-Setup.exe"

if (-not (Test-Path -LiteralPath $setup)) {
    & (Join-Path $root "scripts\build-release.ps1")
}

Start-Process -FilePath $setup -WorkingDirectory (Split-Path -Parent $setup)
