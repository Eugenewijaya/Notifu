# Implementation Plan

## Phase 1 - Local PowerShell MVP

Status: implemented

- PowerShell tray app.
- Windows `UserNotificationListener`.
- All-notification mode plus allow/block list.
- Local AI fallback.
- Local speech fallback.
- Custom floating popup with typewriter chat bubble.
- Desktop pet with live bubble text.
- Expression asset selection by category/urgency.
- Settings UI.
- Startup registry scripts.
- Install/uninstall scripts.

## Phase 2 - AI And Natural Speech

Status: implemented with optional user configuration

- Responses API analysis when `OPENAI_API_KEY` exists.
- Structured notification analysis output.
- OpenAI TTS when voice provider is `openai`.
- Local fallback when key is missing or API call fails.
- Prompting explicitly asks for an original anime-inspired assistant voice, not impersonation.

## Phase 3 - RVC Voice Conversion

Status: adapter implemented, model is user-supplied

- Notifu can generate base audio and pass it through a local RVC wrapper.
- Config supports:
  - `.pth` model path
  - `.index` path
  - Python runtime path
  - method, pitch, index rate, protect, and timeout
- RVC model files are intentionally not part of the public repo.

## Phase 4 - Voice Commands

Status: MVP implemented

- Voice command starts only from popup button, pet click, or tray menu.
- Local commands are mapped to app actions:
  - open app
  - repeat
  - copy reply
  - pause/resume
  - dismiss
- Free-form responses use OpenAI when configured.
- Local speech recognition quality depends on installed Windows recognizers.

## Phase 5 - Open Source Readiness

Status: implemented

- MIT license.
- README with install/test/config/privacy details.
- `.gitignore` excludes `.env.local`, logs, RVC environment, local tool binaries, and shortcuts.
- Generated mascot expression assets are included.
- QRIS placeholder is included, but official QRIS must be supplied by the developer before taking payments.

## Phase 6 - Native Windows App

Status: planned

Prerequisites:

- .NET SDK 8/9 or Windows App SDK.
- WinUI 3 or WPF packaging.
- Proper tray integration.
- MSIX installer.
- Credential storage via Windows Credential Manager or DPAPI.

## Phase 7 - Rich Character Animation

Status: planned

Targets:

- Mouth movement tied to speech playback.
- Blink and idle animation.
- Expression transitions.
- Optional Live2D/Spine-style renderer.
- Per-app mascot behavior rules.

## Phase 8 - Notification Intelligence

Status: planned

Targets:

- Per-contact/app rules.
- Quiet hours.
- Reminder queue.
- Daily summary.
- Sensitive keyword redaction presets.
- Safer draft-reply workflows for supported chat apps.
