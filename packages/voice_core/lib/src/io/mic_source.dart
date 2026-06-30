import 'dart:typed_data';

/// Microphone capture (spec §5, §8.2).
abstract class MicSource {
  /// Begins capturing.
  Future<void> start();

  /// Mono PCM16 frames at [sampleRate].
  Stream<Uint8List> get pcm16;

  /// Half-duplex: called when the AI starts speaking (R7).
  Future<void> pause();

  /// Called when the AI stops speaking.
  Future<void> resume();

  Future<void> stop();

  int get sampleRate;
}
