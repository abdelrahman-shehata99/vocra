# Changelog

## 0.2.1

First pub.dev release (developed in-repo as `voice_core` through 0.1.0).

### Added
- Provider facades `VocraLlm` / `VocraTts` / `VocraStt` (e.g.
  `VocraLlm.openAi(apiKey: ...)`); new `OpenAiLlm` + shared
  `OpenAiCompatibleLlm` base, plus `XaiLlm` (Grok) and `ZaiLlm` (GLM) adapters.
- Typed model/voice catalogs picked by the facades: `GroqModel`, `OpenAiModel`,
  `GeminiModel`, `XaiModel`, `ZaiModel`, `DeepgramVoice`, `ElevenLabsVoice`,
  `ElevenLabsModel`, `DeepgramSttModel` — each with `values`, `.custom(id)`, and
  a `ModelTier`; plus `LlmVendor`/`TtsVendor`/`SttVendor` enums for pickers.
- `VocraPrompt` structured system prompts (`sections`, `json`, `jsonText`) as an
  alternative to `VocraConfig.systemPrompt`.
- Conversation control & retrieval: `conversation`, `messages` (live aggregated
  transcript via `TranscriptAggregator`), `mute`/`unmute`/`isMuted`,
  `endSession()`, `sessionEnded`, `lastReport`, and the `SessionReport` model.
- `VocraConfig.policies` (`SessionPolicies`: max duration, silence timeout, end
  phrases, farewell `endMessage`) and `VocraConfig.assistantName`.
- `Greeting.none()`; `DeepgramStt` `language` parameter.
- `VocraConfig.greeting` (`Greeting.text` / `Greeting.generated`) so the
  assistant can speak first when a conversation starts.
- `VocraConfig.naturalSpeech`: augments the system prompt with a live-voice
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
- **Breaking (rename):** `VoiceConfig` → `VocraConfig`; `systemPrompt` is now
  optional (provide it or `prompt`).
- **Breaking (behavior):** conversation history now resets on each
  `startConversation()` (a session is one conversation).
- **Breaking (interface):** `LlmProvider` and `TtsProvider` gained members
  (`warmUp`, `supportsAudioTags`). Custom providers using `implements` must add
  them; the built-in adapters are updated.
- **Breaking (default):** `GroqLlm` now defaults to `openai/gpt-oss-20b`
  (`llama-3.1-8b-instant` is retired by Groq on 2026-08-16) and sends
  `reasoning_effort: low` / `include_reasoning: false` for `openai/gpt-oss*`.
- Text sent to TTS is now normalized (see `SpeechTextNormalizer`).
- First-turn latency: LLM/TTS network paths are pre-warmed and the mic + STT
  transport start concurrently at conversation start.

### Fixed
- A `MicSource.resume()` failure after a turn now surfaces as a
  `ProviderError(provider: 'microphone')` on the `errors` stream instead of
  escaping as an unhandled async exception.

## 0.1.0

Internal pre-release (git tag `v0.1.0`, never published): streaming
conversation engine (`VoiceEngine`, `TurnMachine`, `AudioQueue`), Groq LLM +
Deepgram STT/TTS adapters, and the typed `VoiceError` hierarchy.
