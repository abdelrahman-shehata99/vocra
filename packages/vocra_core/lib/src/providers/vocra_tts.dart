import '../catalog/deepgram_voices.dart';
import '../catalog/elevenlabs_models.dart';
import '../catalog/elevenlabs_voices.dart';
import 'deepgram_tts.dart';
import 'elevenlabs_tts.dart';
import 'tts_provider.dart';

/// Ready-made text-to-speech providers, one factory per service:
///
/// ```dart
/// tts: VocraTts.elevenLabs(apiKey: elevenLabsKey, voice: ElevenLabsVoice.sarah),
/// ```
///
/// Pick a [voice]/[model] from the catalogs (e.g. `DeepgramVoice.values`,
/// `ElevenLabsVoice.custom('id')`). For advanced knobs (custom base URL,
/// injected Dio) construct [DeepgramTts] or [ElevenLabsTts] directly.
abstract final class VocraTts {
  /// Deepgram Aura.
  static TtsProvider deepgram({
    required String apiKey,
    DeepgramVoice voice = DeepgramVoice.asteria,
  }) => DeepgramTts(apiKey: apiKey, model: voice.id);

  /// ElevenLabs. Use `model: ElevenLabsModel.v3` to enable audio tags like
  /// `[laughs]` (more expressive, higher latency); the default flash model is
  /// fastest.
  static TtsProvider elevenLabs({
    required String apiKey,
    ElevenLabsVoice voice = ElevenLabsVoice.sarah,
    ElevenLabsModel model = ElevenLabsModel.flashV25,
    double stability = 0.5,
    double similarityBoost = 0.75,
    double? style,
    bool? speakerBoost,
  }) => ElevenLabsTts(
    apiKey: apiKey,
    voiceId: voice.id,
    modelId: model.id,
    stability: stability,
    similarityBoost: similarityBoost,
    style: style,
    useSpeakerBoost: speakerBoost,
  );
}
