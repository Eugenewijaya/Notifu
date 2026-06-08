param(
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$app = Join-Path $root "src\Notifu.ps1"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$valueName = "Notifu"
$command = "`"$powershell`" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$app`" -Background"

Set-ItemProperty -Path $runKey -Name $valueName -Value $command

if (-not $Silent) {
    Write-Host "Notifu startup enabled for current Windows user."
    Write-Host "Registry: $runKey\$valueName"
}
