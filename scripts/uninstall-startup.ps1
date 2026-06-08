param(
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$valueName = "Notifu"

if (Get-ItemProperty -Path $runKey -Name $valueName -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKey -Name $valueName
}

if (-not $Silent) {
    Write-Host "Notifu startup disabled for current Windows user."
}
