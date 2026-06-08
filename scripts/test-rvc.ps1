$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root "src\Notifu.Core.psm1") -Force

$settings = Get-NotifuSettings
$settings.voice.provider = "rvc"
Invoke-NotifuSpeech -Text "Halo Evid, ini test suara Notifu memakai backend RVC jika runtime sudah tersedia." -Settings $settings
