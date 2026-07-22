<p align="center">
  <a href="https://www.vocra.cloud">
    <img src="assets/branding/vocra-logo.svg" height="64" alt="Vocra">
  </a>
</p>

<p align="center"><b>Give your app a voice your users can just talk to.</b></p>

[![vocra_flutter](https://img.shields.io/pub/v/vocra_flutter.svg?label=vocra_flutter)](https://pub.dev/packages/vocra_flutter)
[![vocra_core](https://img.shields.io/pub/v/vocra_core.svg?label=vocra_core)](https://pub.dev/packages/vocra_core)
[![CI](https://github.com/abdelrahman-shehata99/vocra/actions/workflows/ci.yml/badge.svg)](https://github.com/abdelrahman-shehata99/vocra/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**[www.vocra.cloud](https://www.vocra.cloud)** — a voice AI SDK for Flutter:
embed a spoken AI conversation in any Android/iOS app — user speaks → STT → LLM
→ spoken reply — with **all orchestration running on-device**. No server, no
recurring backend cost; each app supplies its own provider API keys.

- **LLM:** [Groq](https://groq.com), [OpenAI](https://openai.com), [Gemini](https://ai.google.dev),
  [xAI](https://x.ai), or [Z.ai](https://z.ai) (streaming), with typed model catalogs built in
- **STT:** [Deepgram](https://deepgram.com) (streaming WebSocket)
- **TTS:** [Deepgram](https://deepgram.com) or [ElevenLabs](https://elevenlabs.io)
- **AI speaks first:** optional fixed or LLM-generated greeting
- **Human feel:** optional natural-speech mode with markdown/emoji stripping and
  (on ElevenLabs `eleven_v3`) audio tags like `[laughs]`
- **Full conversation control:** mute, interrupt, a live aggregated transcript,
  session policies (max duration, silence timeout, end phrases), and a
  `SessionReport` when it's over
- **Half-duplex by default** (mic suspended while the AI speaks); optional
  full-duplex barge-in behind native echo cancellation

Providers are pluggable behind interfaces (`LlmProvider`, `TtsProvider`,
`SttTransport`), so new ones can be added without touching the engine.

## Install

```sh
flutter pub add vocra_flutter
```

```dart
import 'package:vocra_flutter/vocra_flutter.dart';

final session = VocraSession(
  config: VocraConfig(
    llm: GroqLlm(apiKey: groqKey),
    stt: DeepgramStt(apiKey: deepgramKey),
    tts: DeepgramTts(apiKey: deepgramKey),
    systemPrompt: 'You are a helpful voice assistant.',
    greeting: const Greeting.text('Hey! What can I help you with?'),
    naturalSpeech: true,
  ),
);

await session.requestPermissions();
session.turnState.listen(updateUi);
await session.start();
```

See the [`vocra_flutter` README](packages/vocra_flutter/README.md) for platform
setup (mic permissions) and the full API.

## Packages

A [melos](https://melos.invertase.dev) monorepo using Dart's native
[pub workspaces](https://dart.dev/tools/pub/workspaces):

```
packages/
  vocra_core/      pure-Dart engine, provider adapters, transport — no Flutter import
  vocra_flutter/   Flutter plugin layer: mic, audio playback, permissions, VocraSession
    example/       runnable demo app
```

- [`vocra_core`](packages/vocra_core/README.md) — the engine (usable without Flutter)
- [`vocra_flutter`](packages/vocra_flutter/README.md) — the app-facing Flutter layer
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — design rationale for the
  non-obvious parts (turn-state, audio ordering, greeting, full-duplex AEC)

## Requirements

- Flutter `>=3.44.0`, Dart `^3.12.0`
- Android and iOS (web/desktop are out of scope)

## Development

```sh
dart pub get                 # resolve the whole workspace
dart run melos bootstrap     # link local packages
dart run melos run analyze   # dart analyze across all packages
dart run melos run format    # check formatting across all packages
dart run melos run test      # dart test (vocra_core) + flutter test (Flutter packages)
```

## License

MIT — see [LICENSE](LICENSE).
