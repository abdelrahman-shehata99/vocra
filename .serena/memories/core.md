Voice AI SDK: on-device voice conversation SDK for Flutter (Android/iOS). Melos+pub-workspaces
monorepo, two packages: `mem:voice_core/core` (pure-Dart engine, no Flutter import) and
`mem:voice_flutter/core` (Flutter plugin layer, depends on voice_core).

Root layout:
- `packages/voice_core/` — engine, provider adapters, transport (see `mem:voice_core/core`)
- `packages/voice_flutter/` — mic/audio/permissions/VoiceSession + `example/` demo app
- `docs/ARCHITECTURE.md` — design rationale for non-obvious deviations from the build spec
  (turn-state machine transitions, AudioQueue contract extensions, Deepgram speech_final vs
  is_final, VoiceSession re-entrancy guards, full-duplex/native AEC). Read before touching
  turn-state, audio queue ordering, or duplex-mode logic — don't rediscover this from code.

Project-wide invariants:
- `voice_core` must never import `package:flutter` — providers/engine are pure Dart, unit
  tested with `dart test`; `voice_flutter` is the only package tested with `flutter test`.
- Providers (`LlmProvider`, `TtsProvider`, `SttTransport`) are pluggable interfaces; current
  concrete impls are Groq (LLM) and Deepgram (STT+TTS) only.
- Half-duplex (mic suspended while AI speaks) is the default; full-duplex requires native AEC
  and is gated — see ARCHITECTURE.md §9 before enabling.

Commands/conventions: `mem:suggested_commands`, `mem:conventions`, `mem:task_completion`.