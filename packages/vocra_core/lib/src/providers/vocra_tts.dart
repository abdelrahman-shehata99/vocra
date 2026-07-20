import 'deepgram_tts.dart';
import 'elevenlabs_tts.dart';
import 'tts_provider.dart';

/// Ready-made text-to-speech providers, one factory per service:
///
/// ```dart
/// tts: VocraTts.elevenLabs(apiKey: elevenLabsKey),
/// ```
///
/// For advanced knobs (custom base URL, injected Dio) construct [DeepgramTts]
/// or [ElevenLabsTts] directly — they implement the same [TtsProvider].
abstract final class VocraTts {
  /// Deepgram Aura. [voice] is the Aura voice model, e.g. `'aura-asteria-en'`.
  static TtsProvider deepgram({
    required String apiKey,
    String voice = 'aura-asteria-en',
  }) => DeepgramTts(apiKey: apiKey, model: voice);

  /// ElevenLabs. Use `model: 'eleven_v3'` to enable audio tags like `[laughs]`
  /// (more expressive, higher latency); the default flash model is fastest.
  static TtsProvider elevenLabs({
    required String apiKey,
    String voiceId = 'EXAVITQu4vr4xnSDxMaL',
    String model = 'eleven_flash_v2_5',
    double stability = 0.5,
    double similarityBoost = 0.75,
    double? style,
    bool? speakerBoost,
  }) => ElevenLabsTts(
    apiKey: apiKey,
    voiceId: voiceId,
    modelId: model,
    stability: stability,
    similarityBoost: similarityBoost,
    style: style,
    useSpeakerBoost: speakerBoost,
  );
}
