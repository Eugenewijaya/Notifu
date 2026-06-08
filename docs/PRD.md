# Product Requirements Document

## Product

Name: Notifu - Your Waifu Notification

Platform: Windows laptop/desktop

Primary user: Windows users who want a local anime-style assistant for incoming notifications.

## Problem

Notifications arrive while users are focused on work. Users want to understand what came in, how urgent it is, and whether they should open the source app, reply later, or ignore it without constantly switching context.

## Goal

Notifu reads Windows toast notifications, summarizes and speaks the important part, displays a floating anime chat bubble, and supports opt-in voice commands for quick interaction.

## Non-Goals

- Reading private databases or message stores.
- Bypassing app encryption.
- Sending messages automatically.
- Running an always-on microphone listener.
- Collecting private user data for the developer.
- Imitating a real person, voice actor, or copyrighted character.

## User Story

As a user, when a notification arrives, I want Notifu to slide in from the right side of the screen, say a short natural message, and let me respond with a click or voice command.

Example:

```text
Evid, ada notifikasi Calendar dari Raka. Katanya: Besok jadi meeting jam sepuluh? Aku bisa bantu siapkan balasan kalau kamu mau.
```

## Requirements

### Notification Listener

- App requests Windows notification listener access.
- App reads active toast notifications.
- App supports `all` mode with blocklist.
- App supports `allowlist` mode for specific app names.
- App deduplicates notifications so repeated toasts are not read continuously.

### AI Analysis

- App produces:
  - `appName`
  - `sender`
  - `summary`
  - `urgency`
  - `category`
  - `announcement`
  - `suggestedReply`
  - `actionHint`
  - `expression`
- If OpenAI key is unavailable, app falls back to local heuristic analysis.
- If OpenAI fails, app logs the failure and continues.

### Voice

- App can speak with local Windows voice.
- App can use OpenAI TTS when `OPENAI_API_KEY` is available and voice provider is `openai`.
- App can use a user-supplied RVC model when voice provider is `rvc`.
- App must not ship third-party voice model files.
- Voice style should be original, playful, natural, and anime-inspired without imitating a real actor or IP.

### Voice Commands

- Voice command is opt-in by button/tray click.
- Commands include:
  - open source app
  - repeat
  - copy draft reply
  - dismiss
  - pause
  - resume
- Free-form conversation can use OpenAI when configured.

### UI

- App has a system tray menu.
- App shows a custom popup instead of Windows balloon notification.
- Popup slides from right to left.
- Popup displays typewriter chat text.
- Desktop pet walks at the bottom of the screen.
- Avatar expression changes based on notification category/urgency.

### Privacy

- App reads only notification text exposed by Windows.
- App does not store notification history by default.
- App does not send developer telemetry.
- Cloud calls happen only with user-provided API key.
- User can disable body reading.

## Acceptance Criteria

- `scripts/test-notifications.ps1 -All` reads current Notification Center items or exits cleanly when none exist.
- `scripts/test-notifications.ps1` filters by current Notifu settings.
- `scripts/test-popup.ps1` shows popup and desktop pet without parse/runtime errors.
- `scripts/run.ps1` starts the tray app.
- `scripts/install.ps1` creates shortcuts and current-user startup registry entry.
- `scripts/uninstall.ps1` removes shortcuts and startup entry.

## Risks

- Windows only exposes notification preview text, not full app data.
- Some apps do not provide useful sender metadata.
- Launching the exact source app is best effort unless Windows exposes an app ID.
- Local Windows speech recognition may not have Indonesian recognizers installed.
- PowerShell MVP is easier to run but less polished than a native packaged app.
