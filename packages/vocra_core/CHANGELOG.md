# Changelog

## 0.2.0

First pub.dev release (developed in-repo as `voice_core` through 0.1.0).

### Added
- `VoiceConfig.greeting` (`Greeting.text` / `Greeting.generated`) so the
  assistant can speak first when a conversation starts.
- `VoiceConfig.naturalSpeech`: augments the system prompt with a live-voice
  style guide (brief spoken replies, contractions, no markdown/emojis), plus
  light audio-tag guidance when the TTS supports tags.
- `SpeechTextNormalizer`: strips markdown, emojis, and unsupported audio tags
  from text before it reaches TTS. Transcripts and history keep the original.
- `VoiceEngine.speak(text)`: speak a scripted assistant utterance (no LLM call).
- `TtsProvider.supportsAudioTags` and `LlmProvider.warmUp`/`TtsProvider.warmUp`.
- `GeminiLlm` (streaming) and `ElevenLabsTts` providers; `ElevenLabsTts` gains
  optional `style` / `useSpeakerBoost` voice settings.
- `DeepgramStt` exposes `endpointing` / `utteranceEnd` tuning parameters.

### Changed
- **Breaking (interface):** `LlmProvider` and `TtsProvider` gained members
  (`warmUp`, `supportsAudioTags`). Custom providers using `implements` must add
  them; the built-in adapters are updated.
- **Breaking (default):** `GroqLlm` now defaults to `openai/gpt-oss-20b`
  (`llama-3.1-8b-instant` is retired by Groq on 2026-08-16) and sends
  `reasoning_effort: low` / `include_reasoning: false` for `openai/gpt-oss*`.
- Text sent to TTS is now normalized (see `SpeechTextNormalizer`).
- First-turn latency: LLM/TTS network paths are pre-warmed and the mic + STT
  transport start concurrently at conversation start.

## 0.1.0

Internal pre-release (git tag `v0.1.0`, never published): streaming
conversation engine (`VoiceEngine`, `TurnMachine`, `AudioQueue`), Groq LLM +
Deepgram STT/TTS adapters, and the typed `VoiceError` hierarchy.
