# vocra_flutter

[![pub package](https://img.shields.io/pub/v/vocra_flutter.svg)](https://pub.dev/packages/vocra_flutter)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/abdelrahman-shehata99/vocra/blob/main/LICENSE)

The Flutter platform layer of **Vocra** — embed a spoken AI conversation
(user speaks → speech-to-text → LLM → spoken reply) in any Android/iOS app,
with **all orchestration on-device**: no server, no recurring backend cost.
Each app supplies its own provider API keys.

This package adds microphone capture, ordered audio playback, permissions, and
audio-session handling on top of the pure-Dart
[`vocra_core`](https://github.com/abdelrahman-shehata99/vocra/tree/main/packages/vocra_core)
engine (which it re-exports, so one import is enough). `VoiceSession` is the
single class most apps touch.

- **Providers:** Groq or Gemini for the LLM; Deepgram or ElevenLabs for TTS;
  Deepgram for STT. All pluggable — pass the provider instance you want.
- **AI speaks first:** an optional `greeting` opens the conversation with a
  fixed line or an LLM-generated one.
- **Human feel:** optional `naturalSpeech` mode nudges the model toward brief,
  spoken-style replies with natural interjections and (on ElevenLabs `eleven_v3`)
  audio tags like `[laughs]`; markdown and emojis are stripped before TTS.
- **Half-duplex by default:** the mic is suspended while the AI speaks, so it
  never hears itself — no native code required. An optional
  [full-duplex mode](https://github.com/abdelrahman-shehata99/vocra/blob/main/docs/ARCHITECTURE.md)
  with native echo cancellation is available but not device-validated.

## Requirements

- Flutter `>=3.44.0`, Dart `^3.12.0`
- Android and iOS only (web/desktop are out of scope)

## Install

```sh
flutter pub add vocra_flutter
```

## Platform setup

**iOS** (`ios/Runner/Info.plist`):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone so you can talk to the AI assistant.</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

The bundled plugins (`permission_handler`, `record`) pick these up
automatically — no Podfile macros or Gradle changes needed.

## Quickstart

```dart
import 'package:vocra_flutter/vocra_flutter.dart';

final session = VoiceSession(
  config: VoiceConfig(
    llm: GroqLlm(apiKey: groqKey),
    stt: DeepgramStt(apiKey: deepgramKey),
    tts: DeepgramTts(apiKey: deepgramKey),
    systemPrompt: 'You are a helpful voice assistant.',
    greeting: const Greeting.text('Hey! What can I help you with?'),
    naturalSpeech: true,
  ),
);

session.turnState.listen(updateUi);   // idle / listening / thinking / speaking
session.transcripts.listen(showBubble);
session.errors.listen(showError);

await session.requestPermissions();
await session.start();
```

That's the whole integration surface. Supply your own provider API keys, listen
to `turnState` / `transcripts` / `metrics` / `errors` to drive your UI, and call
`session.stop()` / `session.dispose()` when done. `session.sendText('...')`
handles typed input (no mic), and `session.speak('...')` speaks a scripted line
in the assistant's voice.

## Example app

[`example/`](https://github.com/abdelrahman-shehata99/vocra/tree/main/packages/vocra_flutter/example)
is a runnable demo: a key-entry screen and a conversation screen (mic toggle,
live transcript, turn-state indicator, latency readout). From
`packages/vocra_flutter/example`, run `flutter run`.

## Errors, interruptions, and routing

- Every failure (auth, rate limit, network, provider) surfaces as a typed
  `VoiceError` on `session.errors` — including mid-stream connection drops —
  never a raw exception.
- Phone-call interruptions and headphone/AirPods disconnects automatically
  interrupt the current turn and return to listening.
- `start()` / `stop()` are safe to call rapidly or concurrently (e.g. a
  double-tapped mic button); re-entrant calls are guarded.

## License

MIT — see [LICENSE](https://github.com/abdelrahman-shehata99/vocra/blob/main/LICENSE).
