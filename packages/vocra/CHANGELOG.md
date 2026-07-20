# Changelog

## 0.2.0

First pub.dev release (developed in-repo as `voice_flutter` through 0.1.0).

### Added
- `VocraSession.speak(text)`: speak a scripted assistant utterance.
- Surfaces the new `vocra_core` 0.2.0 features (greeting, natural speech, TTS
  normalization, ElevenLabs/Gemini providers) through the app-facing API.

### Fixed
- Mic capture falls back to the hardware sample rate (48/44.1 kHz) with
  on-device downsampling to 16 kHz when the platform refuses direct 16 kHz
  capture — fixes "Format conversion is not possible" on the iOS simulator.

### Changed
- Depends on `vocra_core: ^0.2.0`.

## 0.1.0

Internal pre-release (git tag `v0.1.0`, never published): `VocraSession`
app-facing API, mic capture (`record`), ordered playback (`just_audio`),
microphone permissions, audio-session interruption/becoming-noisy handling,
`SecureKeyStore`, an optional native echo-cancellation full-duplex module, and
a runnable example app.
