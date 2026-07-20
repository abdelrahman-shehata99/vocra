import 'dart:typed_data';

/// Streaming linear-interpolation downsampler for mono little-endian PCM16.
///
/// Used by `FlutterMicSource` when the platform refuses to capture at the
/// engine's 16 kHz target directly — notably the iOS simulator, whose input
/// pipeline fails `startStream` at 16 kHz with "Format conversion is not
/// possible". Capture then runs at the hardware rate (48/44.1 kHz) and this
/// converts each frame down to 16 kHz. Linear interpolation is ample for
/// speech STT.
///
/// Stateful across frames: the fractional read position and the previous
/// frame's final sample carry over, so chunk boundaries don't glitch.
/// Create a fresh instance per capture session.
class Pcm16Downsampler {
  Pcm16Downsampler({required this.inputRate, required this.outputRate})
    : assert(
        inputRate >= outputRate,
        'Pcm16Downsampler only downsamples (inputRate >= outputRate).',
      ),
      _step = inputRate / outputRate;

  final int inputRate;
  final int outputRate;
  final double _step;

  // Read position in input samples, on a virtual axis where index 0 is the
  // previous frame's last sample and 1..n are the current frame's samples.
  // Starts at 1.0 so the very first output is the first real sample.
  double _pos = 1.0;
  int _prev = 0;

  /// Converts one capture frame. May return an empty list when the frame is
  /// too short to produce an output sample (the position carries over).
  Uint8List process(Uint8List frame) {
    final n = frame.lengthInBytes ~/ 2; // drop a trailing odd byte, if any
    if (n == 0) return Uint8List(0);
    final input = ByteData.sublistView(frame, 0, n * 2);

    int sampleAt(int i) =>
        i == 0 ? _prev : input.getInt16((i - 1) * 2, Endian.little);

    var pos = _pos;
    final maxOut = ((n - pos) / _step).ceil() + 1;
    final out = ByteData(maxOut < 1 ? 2 : maxOut * 2);
    var count = 0;
    while (pos < n) {
      final i = pos.floor(); // i <= n-1, so i+1 <= n is always readable
      final frac = pos - i;
      final a = sampleAt(i);
      final b = sampleAt(i + 1);
      out.setInt16(count * 2, (a + (b - a) * frac).round(), Endian.little);
      count++;
      pos += _step;
    }
    _pos = pos - n;
    _prev = sampleAt(n);
    return out.buffer.asUint8List(0, count * 2);
  }
}
