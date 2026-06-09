# Notifu Performance Audit

Audit date: 2026-06-09

## Findings

| Area | Before | Native fix |
|---|---|---|
| Idle runtime | Windows PowerShell process measured around 120 MB | Native self-contained tray process measured around 76 MB working set / 28 MB private |
| Popup latency | Popup waited for synchronous AI analysis | Raw notification popup is shown immediately; voice runs afterward |
| Polling | Every 3 seconds | Every 1 second by default |
| Notification order | Notification Center enumeration order | WhatsApp and browsers receive higher priority |
| Desktop pet | Permanent full-body pet and animation timer | Removed from the main runtime |
| Avatar memory | Large expression assets could stay loaded | One resized expression image is loaded only while popup is visible |
| Speech overlap | Multiple voice paths could overlap | One speech queue worker is launched only when needed |
| Distribution | PowerShell shortcuts and scripts | Native app, native setup, Apps & Features uninstaller |

## Runtime Architecture

1. `Notifu.exe` polls Windows Notification Center every second.
2. New notifications are deduplicated and sorted by priority.
3. The cloud popup appears immediately from local notification text.
4. Speech is queued after the popup is visible.
5. RVC/Python exists only during active voice generation, then exits.

## Remaining Cost

RVC uses Python, PyTorch, and the user-supplied model. It can still use substantial
RAM while generating voice. This cost is isolated from the idle Notifu process and
is not started until a notification actually needs speech.

The final self-contained package disables ReadyToRun. In local measurement this
reduced idle memory further while keeping observed startup around 1.8 seconds.
