# Changelog

## 0.2.1

Updates the published 0.2.0 release with the accumulated app-facing API.

### Added
- `VocraSession` (renamed from `VoiceSession`), built on `VocraConfig`.
- `observe({onState, onMessages, onTranscript, onError, onMetrics})` — one-call
  stream wiring returning a cancelable `VocraSubscription`.
- `messages` — a live aggregated conversation stream (interims collapsed).
- `conversation`, `endSession()`, `sessionEnded`, `lastReport` — full
  conversation retrieval and a `SessionReport` on every end path.
- `mute()` / `unmute()` / `isMuted` and a surfaced `interrupt()`.
- Surfaces the new `vocra_core` 0.2.1 features (provider facades, typed model/
  voice catalogs, xAI + Z.ai LLMs, structured prompts, greeting, natural speech,
  session policies) through the app API.

### Fixed
- Mic capture falls back to the hardware sample rate (48/44.1 kHz) with
  on-device downsampling to 16 kHz when the platform refuses direct 16 kHz
  capture — fixes "Format conversion is not possible" on the iOS simulator.
- A mic-resume failure after a turn now surfaces on `errors` instead of crashing.
- Ending a session mid-turn no longer leaves a restarted session's microphone
  permanently unable to reach speech recognition.

### Changed
- **Breaking:** `VoiceSession` → `VocraSession`, `VoiceConfig` → `VocraConfig`.
- Depends on `vocra_core: ^0.2.1`.

### Docs
- iOS setup now documents the required `PERMISSION_MICROPHONE=1` Podfile macro —
  without it `permission_handler` never shows the mic prompt and `start()` fails.
- Branded README with the Vocra logo, badges, and a vocra.cloud website link.

## 0.2.0

Initial pub.dev release: `VoiceSession` app-facing API, mic capture (`record`),
ordered playback (`just_audio`), microphone permissions, audio-session
interruption/becoming-noisy handling, `SecureKeyStore`, an optional native
echo-cancellation full-duplex module, and a runnable example app.
