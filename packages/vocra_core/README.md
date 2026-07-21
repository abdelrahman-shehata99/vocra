# vocra_core

[![pub package](https://img.shields.io/pub/v/vocra_core.svg)](https://pub.dev/packages/vocra_core)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/abdelrahman-shehata99/vocra/blob/main/LICENSE)

Pure-Dart brain of **Vocra**: the conversation engine, sentence-by-sentence
streaming TTS pipeline, half-duplex turn machine, typed model/voice catalogs,
and provider adapters for Groq/OpenAI/Gemini/xAI/Z.ai (LLM), Deepgram (STT/TTS),
and ElevenLabs (TTS).

This package has **no Flutter dependency** — it's plain Dart, fully unit
testable without a device, and reusable from servers or CLIs. Flutter apps
should depend on
[`vocra`](https://pub.dev/packages/vocra) instead, which wires
this engine to the microphone, speaker, and permissions (and re-exports all of
`vocra_core`).

## Install

```sh
dart pub add vocra_core
```

Most apps want `vocra` instead; use `vocra_core` directly only when you
provide your own `AudioSink` / `MicSource` (e.g. a server or custom pipeline).

## What's in here

| Concept | File |
|---|---|
| Orchestrator | `lib/src/engine/voice_engine.dart` |
| Turn state machine | `lib/src/engine/turn_machine.dart` |
| Ordered/parallel audio playback queue | `lib/src/engine/audio_queue.dart` |
| Streaming-token → sentence splitter | `lib/src/engine/sentence_splitter.dart` |
| Markdown/emoji/tag TTS normalizer | `lib/src/engine/speech_text_normalizer.dart` |
| LLM adapters (Groq, Gemini) | `lib/src/providers/*_llm.dart` |
| TTS adapters (Deepgram, ElevenLabs) | `lib/src/providers/*_tts.dart` |
| Deepgram STT adapter | `lib/src/providers/deepgram_stt.dart` |
| Public interfaces (`LlmProvider`, `TtsProvider`, `SttTransport`, `AudioSink`, `MicSource`, `KeyStore`) | `lib/src/providers/*.dart`, `lib/src/io/*.dart` |

Everything is exported from `lib/vocra_core.dart`. See
[`example/main.dart`](example/main.dart) for a Flutter-free tour of the config
surface.

## Features

- **AI speaks first:** `Greeting.text(...)` (instant, no LLM) or
  `Greeting.generated(...)` (LLM-authored opener).
- **Natural speech:** opt-in `naturalSpeech` prompt scaffolding plus automatic
  stripping of markdown/emojis (and unsupported audio tags) from TTS input.
- **Typed errors, end to end:** every failure is a `VoiceError` subtype
  (`AuthError`, `RateLimitError`, `NetworkError`, `ProviderError`,
  `ConfigError`), including mid-stream drops — never a raw exception.

## Extending with a new provider

Implement `LlmProvider`, `TtsProvider`, or `SttTransport` and pass it into
`VocraConfig`. `VoiceEngine` depends only on these abstractions, so a new
provider needs no engine changes.

## Testing

```sh
dart test
```

Unit tests cover the engine, the text normalizer, every provider adapter
(against mocked HTTP/WebSocket fixtures — no real keys or network needed), and
the SSE parser, including split-mid-line SSE events, mid-codepoint UTF-8 splits,
abbreviation/decimal guards, out-of-order clip resolution, epoch-based
interrupts, and 401/429/5xx/network-drop error mapping.

## License

MIT — see [LICENSE](https://github.com/abdelrahman-shehata99/vocra/blob/main/LICENSE).
