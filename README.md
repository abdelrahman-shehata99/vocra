# Voice AI SDK

A reusable Voice AI SDK for Flutter: embed a spoken AI conversation in any
Android/iOS app — user speaks → STT → LLM → spoken reply — with **all
orchestration running on-device**. No server, no recurring backend cost;
each app supplies its own provider API keys.

- **LLM:** [Groq](https://groq.com) (OpenAI-compatible streaming chat completions)
- **STT + TTS:** [Deepgram](https://deepgram.com) (streaming WebSocket STT, REST TTS)
- **Duplex mode:** half-duplex by default — the mic is suspended while the
  AI speaks, so it can't interrupt itself. Full-duplex barge-in is an
  optional, later addition gated behind native echo cancellation.

Providers are pluggable behind interfaces (`LlmProvider`, `TtsProvider`,
`SttTransport`), so Gemini, ElevenLabs, or others can be added later
without touching the engine.

## Packages

This is a [melos](https://melos.invertase.dev) monorepo using Dart's native
[pub workspaces](https://dart.dev/tools/pub/workspaces):

```
packages/
  voice_core/      pure-Dart engine, provider adapters, transport — no Flutter import
  voice_flutter/   Flutter plugin layer: mic, audio playback, permissions, VoiceSession
    example/       runnable demo app + manual test harness
```

See [`packages/voice_core/README.md`](packages/voice_core/README.md) and
[`packages/voice_flutter/README.md`](packages/voice_flutter/README.md) for
package-specific docs, and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for how the engine's streaming/ordering/half-duplex pieces fit together.

## Quickstart

```dart
final session = VoiceSession(
  config: VoiceConfig(
    llm: GroqLlm(apiKey: groqKey),
    tts: DeepgramTts(apiKey: deepgramKey),
    stt: DeepgramStt(apiKey: deepgramKey),
    systemPrompt: 'You are a helpful assistant.',
  ),
);

await session.requestPermissions();
session.turnState.listen(updateUi);
await session.start();
```

## Requirements

- Flutter `>=3.44.0`, Dart SDK `^3.12.0`
- Android and iOS (web is out of scope for v1)
- melos `^8.0.0` for monorepo tooling (`dart pub global activate melos`)

## Development

```sh
dart pub get          # resolves the whole workspace
melos bootstrap        # links local packages together
melos run analyze      # dart analyze across all packages
melos run format        # dart format --set-exit-if-changed across all packages
melos run test          # dart test (voice_core) + flutter test (Flutter packages)
```

## Status

All of `voice_core` (the engine, every provider adapter, and the
orchestrator) is implemented and unit tested with zero device code. The
Flutter platform layer (`voice_flutter`) and example app are implemented
and verified to build and boot on both Android and iOS; the example app
includes a "Test keys" flow so you can verify your own Groq/Deepgram keys
before a full voice round-trip on a physical device.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for design notes,
including a couple of places where the implementation goes slightly beyond
the literal spec text (with rationale) to make the system actually work end
to end.
