# Notifu - Your Waifu Notification

Notifu is an open-source, local-first Windows notification assistant. It watches
Windows Notification Center, immediately slides a small anime cloud popup in from
the right, changes expression based on the message, and reads the notification
through a single voice queue.

![Notifu app icon](assets/notifu-app-icon.png)

## Highlights

- Native Windows `.exe` with a tray menu and standalone Settings window.
- Instant cloud/chat popup with animated typewriter text and expressive anime head.
- Prioritizes WhatsApp and browser notifications before lower-priority apps.
- Reads all Windows notifications by default, with allow/block lists.
- No permanent desktop pet or animation worker while idle.
- One queued voice worker prevents overlapping speech.
- Working local voice by default, with optional user-supplied RVC voice conversion.
- Per-user installer, Start Menu shortcut, startup registration, and uninstaller.
- `Matikan Notifu` is available from tray and Settings.

## Privacy Promise

Notifu is designed to be inspectable and local-first.

- The developer does **not** collect private user data or notification contents.
- This repository has no developer-operated telemetry or analytics server.
- Notifu only reads text exposed by Windows Notification Center.
- Notifu does not read WhatsApp databases, browser databases, or encrypted storage.
- Notification history is not stored by default.
- Voice model files stay on the user's computer and are not included in releases.
- OpenAI requests happen only after the user supplies their own API key and enables AI.

Review the source before installing. The notification, popup, settings, installer,
and uninstaller implementations live under [`native/`](native/).

## Install

### Recommended: GitHub release

1. Download `Notifu-Setup.exe` from the latest GitHub release.
2. Open it and select **Install / Update**.
3. Select **Jalankan Notifu**.
4. Allow notification access when Windows asks.

Notifu installs for the current Windows user in:

```text
%LOCALAPPDATA%\Programs\Notifu
```

Uninstall from Windows **Installed apps**, Start Menu `Notifu.Uninstall.exe`, or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

### Build from source

Requirements:

- Windows 10 version 1809 or newer / Windows 11
- .NET 9 SDK
- Windows PowerShell 5.1 only when using RVC voice

```powershell
git clone https://github.com/Eugenewijaya/Notifu.git
cd Notifu
powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
.\dist\Notifu-Setup.exe
```

The build script creates:

```text
dist\Notifu-Setup.exe   distributable installer
dist\app\Notifu.exe    unpacked native application
```

## Use

Right-click the Notifu tray icon to:

- pause or resume notification handling;
- test the cloud popup;
- open standalone Settings;
- open the runtime log;
- fully stop Notifu.

Double-click the tray icon to open Settings. WhatsApp, Chrome, Microsoft Edge,
Firefox, Brave, and Opera are prioritized by default.

## Configuration

Settings are stored in `config/notifu.settings.json`. Important defaults:

```json
{
  "listener": {
    "pollMilliseconds": 1000
  },
  "notifications": {
    "mode": "all",
    "priorityAppNameContains": [
      "WhatsApp",
      "Chrome",
      "Microsoft Edge",
      "Firefox",
      "Brave",
      "Opera"
    ],
    "blockAppNameContains": ["Notifu"]
  },
  "privacy": {
    "readMessageBody": true,
    "storeHistory": false
  },
  "ui": {
    "enableDesktopPet": false
  }
}
```

Turn off **Bacakan isi pesan** in Settings when notification bodies should remain
hidden. Set notification mode to `allowlist` to process only selected apps.

## Voice

Notifu shows the popup before starting voice work. Voice runs through one queue,
so two notifications cannot talk over each other. Fresh installs use the available
Windows local voice so notifications are never silently dropped.

The repository supports a user-supplied RVC model through
`config/notifu.settings.json`. Put personal model files under the ignored `models/`
folder or use an absolute local path. Installer updates preserve the user's existing
settings. Set `voice.provider` to `rvc` and `voice.rvcOnly` to `true` only after the
Python environment, model, and index paths are configured. RVC/Python can use
substantial RAM while generating audio, but it is not kept alive while Notifu is
idle. Model files are never committed or distributed.

## Test And Development

```powershell
# Build both native projects
.\.dotnet-sdk\dotnet.exe build .\Notifu.sln -c Release

# Preview the native cloud popup
.\dist\app\Notifu.exe --test-popup

# Open native Settings
.\dist\app\Notifu.exe --settings

# Fully stop native and legacy workers
powershell -ExecutionPolicy Bypass -File .\scripts\stop.ps1
```

See [the performance audit](docs/PERFORMANCE_AUDIT.md) for the measured bottlenecks
and architecture changes.

## Project Structure

```text
native/Notifu.App/      Native tray runtime, popup, priority listener, settings
native/Notifu.Setup/    Installer and Apps & Features uninstaller
assets/                 App icon, expressions, and QRIS support poster
config/                 User-editable settings
scripts/                Release build, RVC speech, and fallback utilities
src/                    Legacy PowerShell runtime kept as a fallback
docs/                   Product notes and performance audit
```

## Support Developer

Support development through the official QRIS poster below. Always verify the
merchant name in your payment application before paying.

![Notifu support QRIS](assets/support-qris.png)

## License

MIT. See [LICENSE](LICENSE).
