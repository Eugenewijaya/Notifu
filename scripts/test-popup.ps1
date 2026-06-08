$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root "src\Notifu.Core.psm1") -Force
Import-Module (Join-Path $root "src\Notifu.UI.psm1") -Force

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$settings = Get-NotifuSettings
$analysis = [pscustomobject]@{
    appName = "Calendar"
    sender = "Raka"
    summary = "Besok jadi meeting jam sepuluh?"
    urgency = "normal"
    category = "question"
    announcement = "Evid, ada notifikasi Calendar dari Raka. Katanya: Besok jadi meeting jam sepuluh? Aku bisa bantu siapkan balasan kalau kamu mau."
    suggestedReply = "Jadi, jam 10 oke."
    actionHint = "ask_reply"
    expression = "curious"
}

$popup = Show-NotifuAssistantPopup `
    -Analysis $analysis `
    -Settings $settings `
    -OnOpenApp { [void](Open-NotifuWhatsApp) } `
    -OnCopyReply { [System.Windows.Forms.Clipboard]::SetText($analysis.suggestedReply) } `
    -OnSpeakAgain { Invoke-NotifuSpeech -Text $analysis.announcement -Settings $settings -Async } `
    -OnVoiceCommand { Invoke-NotifuSpeech -Text "Aku dengar, tapi ini cuma test popup." -Settings $settings -Async } `
    -NoShow

[void](Show-NotifuDesktopPet -Settings $settings)
Set-NotifuDesktopPetBubble -Text $analysis.announcement -Expression $analysis.expression -Settings $settings

Invoke-NotifuSpeech -Text $analysis.announcement -Settings $settings -Async

$script:testPopupTimer = New-Object System.Windows.Forms.Timer
$script:testPopupTimer.Interval = 8000
$script:testPopupTimer.Add_Tick({
    $script:testPopupTimer.Stop()
    if ($popup -and -not $popup.IsDisposed) {
        $popup.Close()
    }
})
$script:testPopupTimer.Start()

[System.Windows.Forms.Application]::Run($popup)
