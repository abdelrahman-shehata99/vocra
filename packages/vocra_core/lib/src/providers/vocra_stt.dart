import '../catalog/deepgram_stt_models.dart';
import 'deepgram_stt.dart';
import 'stt_transport.dart';

/// Ready-made speech-to-text providers:
///
/// ```dart
/// stt: VocraStt.deepgram(apiKey: deepgramKey, language: 'en'),
/// ```
///
/// For advanced knobs (custom endpoint, injected WebSocket factory, keep-alive
/// interval) construct [DeepgramStt] directly — it implements the same
/// [SttTransport].
abstract final class VocraStt {
  /// Deepgram streaming STT. [language] is an optional BCP-47 code (omit for
  /// the model default; [DeepgramSttModel.nova3] is best for multilingual).
  /// [endpointing] is the silence-after-speech before finalizing — lower is
  /// snappier but risks cutting off mid-utterance pauses.
  static SttTransport deepgram({
    required String apiKey,
    DeepgramSttModel model = DeepgramSttModel.nova2,
    String? language,
    Duration endpointing = const Duration(milliseconds: 300),
  }) => DeepgramStt(
    apiKey: apiKey,
    model: model.id,
    language: language,
    endpointing: endpointing,
  );
}
