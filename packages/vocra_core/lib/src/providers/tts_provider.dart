import 'dart:typed_data';

import '../util/cancellation.dart';

/// Synthesizes text to speech (spec §5, §7.3).
abstract class TtsProvider {
  /// Synthesizes [text] to encoded audio bytes (e.g. mp3). Respects [cancel].
  Future<Uint8List> synthesize(String text, {required Cancellation cancel});

  /// File extension/mime hint for the returned bytes, e.g. 'mp3'.
  String get audioFormat;

  /// Whether this TTS renders bracketed audio tags like `[laughs]` as delivery
  /// cues rather than reading them aloud. When false (the default), the engine
  /// strips such tags from the text before synthesis so they aren't spoken.
  bool get supportsAudioTags => false;

  /// Optionally pre-establishes the network path (DNS + TCP + TLS) so the
  /// first [synthesize] doesn't pay the handshake (~100–300 ms). Called
  /// fire-and-forget at conversation start; implementations **must swallow all
  /// errors and never throw**. Default: no-op.
  Future<void> warmUp() async {}
}
