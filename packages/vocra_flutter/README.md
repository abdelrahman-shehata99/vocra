# voice_flutter

The Flutter platform layer of the [Voice AI SDK](../../README.md):
microphone capture, ordered audio playback, permissions, audio-session
setup, and `VoiceSession` — the single class apps use to get a spoken AI
conversation with on-device orchestration, no backend required.

Built on [`voice_core`](../voice_core) (the pure-Dart engine), Groq for the
LLM, and Deepgram for STT + TTS. **Half-duplex is the default and
recommended mode**: the mic is suspended while the AI is speaking, so it
can't hear itself — no native code required, and it's what's been verified
end-to-end on both platforms.

An **optional full-duplex mode** (`DuplexMode.fullDuplex`) is also
implemented: the mic stays open and barge-in is detected via STT, backed
by a native echo-cancellation module (`AVAudioEngine` voice processing on
iOS, `AudioRecord` + `AcousticEchoCanceler` on Android). That native code
compiles cleanly on both platforms but its actual echo-cancellation
quality hasn't been validated on a physical device — see
[`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md#full-duplex--native-aec-spec-9-t18--optional)
before relying on it. Check `NativeAecMicSource.isAvailable()` before
using it; `VoiceSession` will refuse to start (with a `ConfigError`,
not a crash) if you request full-duplex without it.

## Requirements

- Flutter `>=3.44.0`, Dart SDK `^3.12.0`
- Android and iOS only for v1 (web is out of scope)

## Install

```yaml
dependencies:
  voice_flutter:
    git:
      url: <this repo>
      path: packages/voice_flutter
```

(Not yet published to pub.dev — see [the root README](../../README.md) for
the monorepo layout.)

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

Both plugins (`permission_handler`, `record`) pick these up automatically —
no Podfile macros or Gradle changes needed for v1.

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

That's the whole integration surface: provide your own Groq + Deepgram API
keys, listen to `turnState` / `transcripts` / `metrics` / `errors` to drive
your UI, and call `session.stop()` / `session.dispose()` when done.
`session.sendText('...')` lets you skip the mic entirely for typed input.

## Example app

`example/` is a runnable demo: a key-entry screen (with a "Test keys"
button that does one cheap call against each provider) and a conversation
screen (mic toggle, live transcript, turn-state indicator, latency
readout). Run it from `packages/voice_flutter/example`:

```sh
flutter run
```

## Errors, interruptions, and routing

- Every failure (auth, rate limit, network, provider error) surfaces as a
  typed `VoiceError` on `session.errors` — including connection drops
  mid-stream — never a raw exception.
- Phone-call interruptions and headphone/AirPods disconnects
  (`audio_session`) automatically interrupt the current turn and return to
  listening rather than continuing to talk over them.
- `start()` / `stop()` are safe to call rapidly/concurrently (e.g. a
  double-tapped mic button) — re-entrant calls are guarded and a no-op.
