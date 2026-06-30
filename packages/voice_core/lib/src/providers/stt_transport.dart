import 'dart:typed_data';

import '../models/transcript_event.dart';

/// A streaming speech-to-text transport (spec §5, §7.2).
abstract class SttTransport {
  /// Opens the streaming connection.
  Future<void> start();

  /// Pushes raw PCM16 mono frames at [sampleRate].
  void sendAudio(Uint8List pcm16);

  /// Interim and final user transcripts.
  Stream<TranscriptEvent> get transcripts;

  /// Flushes and closes the connection.
  Future<void> stop();

  Future<void> dispose();

  /// e.g. 16000.
  int get sampleRate;
}
