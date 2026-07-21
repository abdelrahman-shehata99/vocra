# vocra

[![pub package](https://img.shields.io/pub/v/vocra.svg)](https://pub.dev/packages/vocra)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/abdelrahman-shehata99/vocra/blob/main/LICENSE)

**On-device voice AI for Flutter.** The user speaks, an AI replies out loud —
speech-to-text → LLM → text-to-speech, all orchestrated on the device. No
backend, no per-minute platform fees: each app brings its own provider API keys.

- **Pluggable providers** — LLM: Groq, OpenAI, Gemini, xAI, Z.ai · STT: Deepgram
  · TTS: Deepgram, ElevenLabs. Swap any of them in one line, with typed model &
  voice catalogs built in.
- **AI speaks first** — an optional greeting (fixed or LLM-generated).
- **Human feel** — natural-speech mode for brief, spoken-style replies;
  `[laughs]`-style audio tags on ElevenLabs v3.
- **Full conversation control** — mute, interrupt, a live aggregated transcript,
  session policies (max duration, silence timeout, end phrases, farewell), and a
  `SessionReport` when it's over.
- **Half-duplex by default** (the mic is suspended while the AI talks, so it
  never hears itself). Optional full-duplex barge-in with native echo
  cancellation.

## Install

```sh
flutter pub add vocra
```

Requires Flutter `>=3.44.0`, Dart `^3.12.0`. Android and iOS only.

## Platform setup

**iOS** (`ios/Runner/Info.plist`):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone so you can talk to the AI assistant.</string>
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

## Quickstart

```dart
import 'package:vocra/vocra.dart';

final session = VocraSession(
  config: VocraConfig(
    llm: VocraLlm.openAi(apiKey: openAiKey),
    stt: VocraStt.deepgram(apiKey: deepgramKey),
    tts: VocraTts.elevenLabs(apiKey: elevenLabsKey),
    systemPrompt: 'You are a friendly cooking assistant.',
    greeting: const Greeting.text('Hey! What are we cooking today?'),
    naturalSpeech: true,
  ),
);

final sub = session.observe(
  onState: (state) => print(state),            // idle / listening / thinking / speaking
  onMessages: (messages) => render(messages),  // the live conversation
  onError: (error) => showError(error.message),
);

await session.start();   // asks for mic permission, opens the audio session, starts listening
// ... later:
final report = await session.endSession();  // stops and returns a SessionReport
await sub.cancel();
await session.dispose();
```

That's the whole surface. Pick providers with the `VocraLlm` / `VocraTts` /
`VocraStt` factories, drive your UI from `observe`, and end with `stop()` /
`endSession()` / `dispose()`.

## Providers

| Kind | Factory | Catalog / notes |
|---|---|---|
| LLM | `VocraLlm.groq(apiKey:, model:)` | `GroqModel` — default GPT-OSS 20B |
| LLM | `VocraLlm.openAi(apiKey:, model:)` | `OpenAiModel` — default GPT-4.1 Mini |
| LLM | `VocraLlm.gemini(apiKey:, model:)` | `GeminiModel` — default 2.5 Flash |
| LLM | `VocraLlm.xai(apiKey:, model:)` | `XaiModel` — Grok |
| LLM | `VocraLlm.zai(apiKey:, model:)` | `ZaiModel` — GLM |
| STT | `VocraStt.deepgram(apiKey:, model:, language:)` | `DeepgramSttModel` (nova-2 / nova-3) |
| TTS | `VocraTts.deepgram(apiKey:, voice:)` | `DeepgramVoice` (12 Aura voices) |
| TTS | `VocraTts.elevenLabs(apiKey:, voice:, model:)` | `ElevenLabsVoice` / `ElevenLabsModel` (v3 = `[laughs]` tags) |

### Model & voice catalogs

Every provider ships a typed catalog, so you never hand-maintain model lists.
Pick a constant, enumerate `.values` for a dropdown, or use `.custom('id')` for
anything newer than the SDK:

```dart
llm: VocraLlm.xai(apiKey: xaiKey, model: XaiModel.grok45),
tts: VocraTts.elevenLabs(apiKey: elKey, voice: ElevenLabsVoice.rachel),

// Build a picker straight from the catalog:
for (final m in GroqModel.values) Text('${m.displayName} — ${m.tier?.displayName}');
// Or an id the catalog doesn't list yet:
llm: VocraLlm.openAi(apiKey: key, model: const OpenAiModel.custom('gpt-5')),
```

Every catalog entry is a `CatalogEntry` (`id`, `displayName`, `note`); model
catalogs also carry a `ModelTier` (budget / balanced / flagship).

Need a custom base URL or client? Construct the underlying adapter
(`GroqLlm`, `OpenAiLlm`, `XaiLlm`, `ZaiLlm`, `DeepgramTts`, …) directly — they
satisfy the same interfaces and slot into `VocraConfig` too.

## Structured prompts

For multi-section personas or JSON context, use `prompt:` instead of
`systemPrompt:`:

```dart
prompt: VocraPrompt.sections([
  PromptSection('Persona', 'You are Riley, a warm scheduling assistant.'),
  PromptSection.json('Business hours', {'mon-fri': '9-5', 'sat': '10-2'}),
]),
```

Load JSON from a file/asset yourself and pass it to
`PromptSection.jsonText(title, jsonString)`.

## Greeting

- `Greeting.text('Hi! How can I help?')` — spoken instantly, no LLM call.
- `Greeting.generated()` — the LLM writes the opener from your persona.
- `Greeting.none()` (or leave `greeting` null) — the user speaks first.

## Session policies

```dart
policies: SessionPolicies(
  maxDuration: Duration(minutes: 10),
  silenceTimeout: Duration(seconds: 30),
  endPhrases: ['goodbye', 'talk to you later'],
  endMessage: 'Thanks for calling. Take care!',   // spoken before auto-ends
),
assistantName: 'Riley',
```

Any policy ends the session automatically (speaking `endMessage` first, if set)
and emits a `SessionReport` on `session.sessionEnded`.

## Control & retrieval

- `session.mute()` / `unmute()` / `isMuted` — gate the mic without stopping it.
- `session.interrupt()` — cut the current reply, back to listening.
- `session.sendText('...')` — typed input; `session.speak('...')` — scripted
  assistant line.
- `session.conversation` — the messages so far; `session.messages` — a live
  stream of the aggregated transcript.
- `session.sessionEnded` / `session.endSession()` — a `SessionReport` with the
  messages, duration, turn count, and why it ended.

## Errors & metrics

Every failure (auth, rate limit, network, provider) surfaces as a typed
`VoiceError` on `errors` — including mid-stream drops — never a raw exception.
Per-turn latency (`ttft`, `timeToFirstVoice`, `total`, …) arrives as
`TurnMetrics` via `observe(onMetrics:)`.

## License

MIT — see [LICENSE](https://github.com/abdelrahman-shehata99/vocra/blob/main/LICENSE).
