/// The pure-Dart brain of the Vocra voice AI SDK.
///
/// Vocra embeds a spoken AI conversation — the user speaks, speech-to-text
/// transcribes, an LLM replies, and text-to-speech speaks the reply — with all
/// orchestration on-device. This package has **no Flutter dependency**; Flutter
/// apps should depend on `vocra_flutter`, which wires this engine to the
/// microphone, audio playback, and permissions.
///
/// The entry points are [VoiceEngine] (the orchestrator) and [VocraConfig]
/// (the config surface). Providers are pluggable behind three interfaces —
/// [LlmProvider], [SttTransport], and [TtsProvider] — with Groq/OpenAI/Gemini/
/// xAI/Z.ai (LLM) and Deepgram/ElevenLabs (STT/TTS) adapters included. Ready-to-
/// pick model and voice catalogs ([GroqModel], [DeepgramVoice], …) power the
/// [VocraLlm]/[VocraTts]/[VocraStt] factories. Every provider and engine failure
/// surfaces as a typed [VoiceError], including mid-stream drops.
library;

export 'src/catalog/catalog_entry.dart';
export 'src/catalog/vendors.dart';
export 'src/catalog/groq_models.dart';
export 'src/catalog/openai_models.dart';
export 'src/catalog/gemini_models.dart';
export 'src/catalog/xai_models.dart';
export 'src/catalog/zai_models.dart';
export 'src/catalog/deepgram_voices.dart';
export 'src/catalog/elevenlabs_voices.dart';
export 'src/catalog/elevenlabs_models.dart';
export 'src/catalog/deepgram_stt_models.dart';

export 'src/models/chat_message.dart';
export 'src/models/turn_state.dart';
export 'src/models/transcript_event.dart';
export 'src/models/turn_metrics.dart';
export 'src/models/voice_error.dart';
export 'src/models/vocra_config.dart';
export 'src/models/greeting.dart';
export 'src/models/vocra_prompt.dart';
export 'src/models/session_report.dart';
export 'src/models/session_policies.dart';

export 'src/io/audio_sink.dart';
export 'src/io/mic_source.dart';
export 'src/io/key_store.dart';

export 'src/providers/llm_provider.dart';
export 'src/providers/openai_compatible_llm.dart';
export 'src/providers/openai_llm.dart';
export 'src/providers/tts_provider.dart';
export 'src/providers/stt_transport.dart';
export 'src/providers/groq_llm.dart';
export 'src/providers/gemini_llm.dart';
export 'src/providers/deepgram_tts.dart';
export 'src/providers/elevenlabs_tts.dart';
export 'src/providers/deepgram_stt.dart';
export 'src/providers/vocra_llm.dart';
export 'src/providers/vocra_tts.dart';
export 'src/providers/vocra_stt.dart';

export 'src/transport/sse_parser.dart';

export 'src/engine/sentence_splitter.dart';
export 'src/engine/speech_text_normalizer.dart';
export 'src/engine/transcript_aggregator.dart';
export 'src/engine/audio_queue.dart';
export 'src/engine/turn_machine.dart';
export 'src/engine/voice_engine.dart';

export 'src/util/cancellation.dart';
