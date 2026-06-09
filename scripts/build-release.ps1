param(
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dotnet = Join-Path $root ".dotnet-sdk\dotnet.exe"
if (-not (Test-Path -LiteralPath $dotnet)) {
    $dotnet = (Get-Command dotnet -ErrorAction Stop).Source
}

$dist = Join-Path $root "dist"
$appOut = Join-Path $dist "app"
$setupOut = Join-Path $dist "setup"
$payloadDir = Join-Path $root "native\Notifu.Setup\Payload"
$payloadZip = Join-Path $payloadDir "Notifu.Payload.zip"

Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $payloadDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $appOut, $setupOut, $payloadDir -Force | Out-Null

$selfContained = if ($FrameworkDependent) { "false" } else { "true" }
& $dotnet publish (Join-Path $root "native\Notifu.App\Notifu.App.csproj") `
    -c Release -r win-x64 --self-contained $selfContained -o $appOut

Copy-Item (Join-Path $root "assets") $appOut -Recurse -Force
Copy-Item (Join-Path $root "config") $appOut -Recurse -Force
Copy-Item (Join-Path $root "scripts") $appOut -Recurse -Force
Copy-Item (Join-Path $root "src") $appOut -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $appOut "logs") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $appOut "models") -Force | Out-Null

Compress-Archive -Path (Join-Path $appOut "*") -DestinationPath $payloadZip -CompressionLevel Optimal -Force
& $dotnet publish (Join-Path $root "native\Notifu.Setup\Notifu.Setup.csproj") `
    -c Release -r win-x64 --self-contained true -o $setupOut

Copy-Item (Join-Path $setupOut "Notifu.Setup.exe") (Join-Path $dist "Notifu-Setup.exe") -Force
Write-Host "Release built:"
Write-Host "  App: $appOut\Notifu.exe"
Write-Host "  Installer: $dist\Notifu-Setup.exe"
