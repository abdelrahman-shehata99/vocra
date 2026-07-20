# CLAUDE.md

## AI Assistant Role

Act as a **senior Dart/Flutter SDK engineer**:
- Be precise and conservative — this is a published-package codebase; every public API is a
  compatibility surface, not just an internal detail.
- Prefer minimal, targeted changes. Don't "improve" adjacent code you weren't asked to touch.
- Follow existing patterns and conventions already in the codebase (see Conventions below).
- Verify assumptions by reading existing code first — especially `docs/ARCHITECTURE.md`, which
  documents several intentional, non-obvious deviations from the original build spec.
- If uncertain or multiple interpretations exist, state assumptions explicitly and ask rather
  than guessing.

## Project Context

Voice AI SDK: embed a spoken AI conversation (user speaks → STT → LLM → spoken reply) in any
Android/iOS Flutter app, with **all orchestration on-device** — no server, no recurring backend
cost. Each host app supplies its own provider API keys (Groq for LLM, Deepgram for STT+TTS).

**Always run `melos run analyze` after code changes.**

## Quick Reference

| Command | Purpose |
|---|---|
| `dart pub get` | Resolve the whole workspace |
| `melos bootstrap` | Link local packages together (after clone / dependency changes) |
| `melos run analyze` | `dart analyze .` across all packages |
| `melos run format` | `dart format --set-exit-if-changed .` across all packages (check only, no auto-fix) |
| `melos run test` | `dart test` (vocra_core) + `flutter test` (vocra) |
| `cd packages/vocra_core && dart test` | Faster iteration on just the engine package |
| `cd packages/vocra && flutter test` | Faster iteration on just the platform layer |
| `cd packages/vocra/example && flutter run` | Run the demo app (needs device/simulator + a "Test keys" flow for Groq/Deepgram keys) |

## Architecture

**Pattern**: melos + Dart-native pub workspaces monorepo, two packages, strict one-way dependency.

```
packages/
├── vocra_core/      # pure-Dart engine, provider adapters, transport — NO Flutter import
│   └── lib/src/
│       ├── engine/      # VoiceEngine (orchestrator), TurnMachine, AudioQueue, SentenceSplitter
│       ├── providers/   # GroqLlm, DeepgramStt, DeepgramTts + Llm/Stt/Tts interfaces
│       ├── io/           # AudioSink / MicSource / KeyStore interfaces (implemented in vocra)
│       ├── models/       # VoiceConfig, VoiceError, TurnState, TurnMetrics, ChatMessage, TranscriptEvent
│       ├── transport/    # SseParser (Groq streaming)
│       └── util/         # Cancellation
└── vocra/   # Flutter plugin layer: mic, audio playback, permissions, VoiceSession
    ├── lib/src/          # FlutterMicSource, FlutterAudioSink, NativeAecMicSource, SecureKeyStore,
    │                     # AudioSessionSetup, MicPermission, VoiceSession (app-facing API)
    ├── ios/Classes/      # AecAudioEngine.swift (native echo cancellation, optional full-duplex)
    ├── android/          # AecAudioRecorder.kt equivalent (same purpose)
    └── example/          # runnable demo app + manual test harness (key entry → conversation screen)
```

### Key invariants
- `vocra_core` must **never** import `package:flutter`. Anything Flutter-specific belongs in
  `vocra`, wired into `vocra_core` through the `AudioSink` / `MicSource` / `KeyStore`
  interfaces in `lib/src/io/`.
- `TurnMachine` (`packages/vocra_core/lib/src/engine/turn_machine.dart`) is the **sole** owner
  of turn-state transitions (`idle → listening → thinking → speaking → listening`, plus any
  state → `idle` on stop). Only `VoiceEngine` drives it — this is what makes "mic must not
  reach STT while the AI is speaking" (half-duplex) enforceable in one place. Don't transition
  turn state from anywhere else, even for edge cases.
- All provider/engine failures surface as a typed `VoiceError` subtype (`AuthError`,
  `RateLimitError`, `NetworkError`, `ProviderError`, `ConfigError` —
  `packages/vocra_core/lib/src/models/voice_error.dart`), **including mid-stream failures**
  (a dropped SSE stream from Groq, a WebSocket that closes mid-conversation from Deepgram).
  Never let a raw provider exception leak out of an adapter or the engine.
- Providers (`LlmProvider`, `TtsProvider`, `SttTransport`) are pluggable interfaces — current
  concrete impls are Groq (LLM) and Deepgram (STT+TTS) only. New providers implement the
  interface; nothing in the engine should assume Groq/Deepgram specifics.
- `VoiceSession.start()` / `stop()` each set a re-entrancy guard flag **synchronously, before
  the first `await`**, so two rapid calls (e.g. a double-tapped mic button) can't both slip
  past an "already started" check. Follow this pattern for any new start/stop-style guarded
  method.
- Half-duplex (mic suspended while the AI speaks) is the default. Full-duplex barge-in requires
  native echo cancellation (`NativeAecMicSource.isAvailable()`) and is gated: `VoiceSession`
  emits a `ConfigError` and refuses to start rather than silently downgrading if full-duplex was
  requested but AEC isn't available.

**Read `docs/ARCHITECTURE.md` before touching turn-state transitions, `AudioQueue` ordering
(`completeTurn`/`drained`/`clipStarted`), the Deepgram `speech_final` vs `is_final` mapping, or
full-duplex/native-AEC logic** — it documents *why* each of these extends beyond the literal
build spec, with rationale, so you don't need to rediscover it from the diff.

### Key Files
- [packages/vocra_core/lib/src/engine/voice_engine.dart](packages/vocra_core/lib/src/engine/voice_engine.dart) — the orchestrator; drives `TurnMachine`, wires STT/LLM/TTS together
- [packages/vocra_core/lib/src/engine/turn_machine.dart](packages/vocra_core/lib/src/engine/turn_machine.dart) — turn-state transition rules
- [packages/vocra_core/lib/src/engine/audio_queue.dart](packages/vocra_core/lib/src/engine/audio_queue.dart) — ordered TTS clip playback + interruption
- [packages/vocra_core/lib/src/models/voice_config.dart](packages/vocra_core/lib/src/models/voice_config.dart) — public config surface (`DuplexMode`, `BargeInSensitivity`, provider wiring)
- [packages/vocra_core/lib/src/models/voice_error.dart](packages/vocra_core/lib/src/models/voice_error.dart) — typed error hierarchy
- [packages/vocra/lib/src/voice_session.dart](packages/vocra/lib/src/voice_session.dart) — the app-facing entry point (`VoiceSession`)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design rationale for non-obvious spec deviations

## Development Conventions

### Code Style
- `dart format .` (or `melos run format` to check) before commits.
- Default `lints` (vocra_core) / `flutter_lints` (vocra) — no project-specific
  analysis_options beyond the example app's.

### Testing
- `vocra_core`: `package:test` + `mocktail` for mocking; `stream_channel` /
  `test/providers/fake_websocket_channel.dart` fakes for WebSocket-based providers (Deepgram).
- `vocra`: `flutter_test`.
- Test files mirror `lib/src/...` structure under `test/...`.
- Non-obvious behavioral decisions get a **dedicated named test** describing the decision (e.g.
  `deepgram_stt_test.dart`'s *"maps speech_final ... not raw is_final"*) rather than being
  asserted incidentally inside an unrelated test — grep test descriptions before assuming a
  behavior is untested.

### Error Handling
- Don't let raw exceptions cross a provider/engine boundary — map to the closest `VoiceError`
  subtype (see Key invariants above).

### Reading & Research Efficiency
- Prefer Serena's semantic tools (`get_symbols_overview`, `find_symbol`,
  `find_referencing_symbols`) over reading whole files, especially in `voice_engine.dart` and
  `voice_session.dart` which have many interacting methods. Use `rename_symbol` /
  `safe_delete_symbol` for reference-aware refactors instead of manual find-and-replace.

## Configuration

- **Version**: `0.1.0` (pre-release, both packages) — see each package's `pubspec.yaml`.
- **Dart SDK**: `^3.12.0`; **Flutter**: `>=3.44.0`.
- **Platforms**: Android and iOS only (web is explicitly out of scope for v1).
- **iOS native**: CocoaPods, not Swift Package Manager (intentional — see
  `docs/ARCHITECTURE.md` §Full-duplex for rationale).

## Reference Docs

| Doc | Read when |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Touching turn-state, `AudioQueue`, Deepgram final-transcript mapping, `VoiceSession` re-entrancy,/ or full-duplex/native-AEC logic |
| [packages/vocra_core/README.md](packages/vocra_core/README.md) | Working on the engine/provider-adapter package specifically |
| [packages/vocra/README.md](packages/vocra/README.md) | Working on the Flutter platform layer specifically |
| [packages/vocra/example/README.md](packages/vocra/example/README.md) | Running/modifying the demo app |

## Git Workflow

- Commit messages: present tense, one logical change per commit (see `git log` for style, e.g.
  "Fix race conditions and improve speech/audio reliability").
- No CI/branch-protection config is present in this repo yet — confirm with the user before
  assuming any particular branch or PR convention.
