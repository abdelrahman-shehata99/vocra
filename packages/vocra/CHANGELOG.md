# Changelog

## 0.2.0

First pub.dev release of the Vocra Flutter package (developed in-repo as
`voice_flutter` through 0.1.0, renamed to `vocra`).

### Added
- `VocraSession` (renamed from `VoiceSession`), built on `VocraConfig`.
- `observe({onState, onMessages, onTranscript, onError, onMetrics})` — one-call
  stream wiring returning a cancelable `VocraSubscription`.
- `messages` — a live aggregated conversation stream (interims collapsed).
- `conversation`, `endSession()`, `sessionEnded`, `lastReport` — full
  conversation retrieval and a `SessionReport` on every end path.
- `mute()` / `unmute()` / `isMuted` and a surfaced `interrupt()`.
- Surfaces the new `vocra_core` 0.2.0 features (provider facades, typed model/
  voice catalogs, xAI + Z.ai LLMs, structured prompts, greeting, natural speech,
  session policies) through the app API.

### Fixed
- Mic capture falls back to the hardware sample rate (48/44.1 kHz) with
  on-device downsampling to 16 kHz when the platform refuses direct 16 kHz
  capture — fixes "Format conversion is not possible" on the iOS simulator.
- A mic-resume failure after a turn now surfaces on `errors` instead of crashing.

### Changed
- **Package renamed** `voice_flutter` → `vocra`
  (`import 'package:vocra/vocra.dart'`).
- `VoiceSession` → `VocraSession`, `VoiceConfig` → `VocraConfig`.
- Depends on `vocra_core: ^0.2.0`.
