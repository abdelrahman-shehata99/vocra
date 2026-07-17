import 'dart:typed_data';

/// Ordered, instantly-stoppable audio playback (spec §5, §6.2).
abstract class AudioSink {
  /// Enqueues a clip with a strict play order [index]. Clips must play in
  /// ascending index order regardless of arrival order.
  Future<void> enqueue(int index, Uint8List bytes, String format);

  /// Stops immediately, drops everything queued, and ignores late arrivals
  /// from before this call (epoch bump is handled by the engine/AudioQueue).
  Future<void> stopNow();

  /// 0..1 amplitude for UI visualizer (optional — may be a no-op stream).
  Stream<double> get amplitude;

  /// Emits when a clip finishes playing.
  Stream<void> get clipFinished;

  Future<void> dispose();
}
