# voice_core

Pure-Dart brain of the [Voice AI SDK](../../README.md): the conversation
engine, sentence-by-sentence streaming TTS pipeline, half-duplex turn
machine, and provider adapters for Groq (LLM) and Deepgram (STT/TTS).

This package has **no Flutter dependency** — it's plain Dart and fully unit
testable without a device or simulator. The platform layer (microphone
capture, audio playback, permissions) lives in the sibling
[`voice_flutter`](../voice_flutter) package, which most apps should depend
on instead of this one directly.

## What's in here

| Concept | File |
|---|---|
| Orchestrator | `lib/src/engine/voice_engine.dart` |
| Turn state machine | `lib/src/engine/turn_machine.dart` |
| Ordered/parallel audio playback queue | `lib/src/engine/audio_queue.dart` |
| Streaming-token → sentence splitter | `lib/src/engine/sentence_splitter.dart` |
| Groq LLM adapter | `lib/src/providers/groq_llm.dart` |
| Deepgram STT adapter | `lib/src/providers/deepgram_stt.dart` |
| Deepgram TTS adapter | `lib/src/providers/deepgram_tts.dart` |
| SSE byte-stream parser | `lib/src/transport/sse_parser.dart` |
| Public interfaces (`LlmProvider`, `TtsProvider`, `SttTransport`, `AudioSink`, `MicSource`, `KeyStore`) | `lib/src/providers/*.dart`, `lib/src/io/*.dart` |

Everything is exported from `lib/voice_core.dart`.

## Requirements

- Dart SDK `^3.12.0`

## Testing

```sh
dart test
```

82+ unit tests cover the engine, every provider adapter (against mocked
HTTP/WebSocket fixtures — no real API keys or network access needed), and
the SSE parser, including edge cases like split-mid-line SSE events,
mid-codepoint UTF-8 splits, abbreviation/decimal guards in sentence
splitting, out-of-order TTS clip resolution, epoch-based interrupt
handling, and 401/429/5xx/network-drop error mapping.

## Extending with a new provider

Implement the relevant interface — `LlmProvider`, `TtsProvider`, or
`SttTransport` — and pass it into `VoiceConfig`. `VoiceEngine` only depends
on these abstractions, never on Groq/Deepgram concretely, so a new provider
needs no engine changes.

## Errors

Every failure surfaces as a typed `VoiceError` subtype — `AuthError`,
`RateLimitError`, `NetworkError`, `ProviderError`, `ConfigError` — never a
raw exception or string, including failures that occur mid-stream (a
dropped connection after an LLM/TTS/STT call already started).
