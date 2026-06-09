param(
    [switch]$KeepSpeechQueue,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$currentProcessId = $PID
$nativeCandidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Notifu\Notifu.exe"),
    (Join-Path $root "dist\app\Notifu.exe")
)
foreach ($native in $nativeCandidates) {
    if (Test-Path -LiteralPath $native) {
        try {
            Start-Process -FilePath $native -ArgumentList "--shutdown" -WindowStyle Hidden -Wait
        } catch {}
    }
}

function Test-ContainsIgnoreCase {
    param(
        [string]$Text,
        [string]$Value
    )

    return $Text.IndexOf($Value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-NotifuRuntimeProcesses {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $currentProcessId -and
            $_.CommandLine -and
            (Test-ContainsIgnoreCase -Text $_.CommandLine -Value $root) -and
            (
                (Test-ContainsIgnoreCase -Text $_.CommandLine -Value "src\Notifu.ps1") -or
                (Test-ContainsIgnoreCase -Text $_.CommandLine -Value "scripts\process-speech-queue.ps1") -or
                (Test-ContainsIgnoreCase -Text $_.CommandLine -Value "scripts\speak-text.ps1") -or
                (Test-ContainsIgnoreCase -Text $_.CommandLine -Value "scripts\notifu_rvc.py")
            )
        })
}

for ($pass = 1; $pass -le 3; $pass++) {
    $targets = Get-NotifuRuntimeProcesses
    if (-not $targets) {
        break
    }

    foreach ($process in $targets) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
            if (-not $Silent) {
                Write-Host "Stopped Notifu process $($process.ProcessId) ($($process.Name))."
            }
        } catch {
            if (-not $Silent) {
                Write-Warning "Unable to stop Notifu process $($process.ProcessId): $($_.Exception.Message)"
            }
        }
    }

    Start-Sleep -Milliseconds 350
}

if (-not $KeepSpeechQueue) {
    $queueDir = Join-Path $root "logs\speech-queue"
    if (Test-Path -LiteralPath $queueDir) {
        Get-ChildItem -LiteralPath $queueDir -Filter "*.txt" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

$remaining = Get-NotifuRuntimeProcesses
if ($remaining) {
    throw "Notifu could not fully stop. Remaining process IDs: $(@($remaining.ProcessId) -join ', ')"
}

if (-not $Silent) {
    Write-Host "Notifu is fully stopped."
}
