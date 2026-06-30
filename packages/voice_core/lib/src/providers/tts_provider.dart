import 'dart:typed_data';

import '../util/cancellation.dart';

/// Synthesizes text to speech (spec §5, §7.3).
abstract class TtsProvider {
  /// Synthesizes [text] to encoded audio bytes (e.g. mp3). Respects [cancel].
  Future<Uint8List> synthesize(String text, {required Cancellation cancel});

  /// File extension/mime hint for the returned bytes, e.g. 'mp3'.
  String get audioFormat;
}
