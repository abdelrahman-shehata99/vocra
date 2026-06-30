import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:voice_core/voice_core.dart';

/// Implements [MicSource] via `record` (spec §8.2): streams mono PCM16
/// frames at 16 kHz.
///
/// [pause]/[resume] gate the existing stream rather than stopping/restarting
/// native capture, per the spec's explicit preference ("prefer keeping
/// capture open and gating the stream to avoid restart latency") — this
/// matters for half-duplex, where pause/resume happens on every turn.
class FlutterMicSource implements MicSource {
  FlutterMicSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  static const int _sampleRate = 16000;

  StreamSubscription<Uint8List>? _captureSub;
  final StreamController<Uint8List> _pcm16Controller =
      StreamController<Uint8List>.broadcast();

  bool _forwarding = true;

  @override
  int get sampleRate => _sampleRate;

  @override
  Stream<Uint8List> get pcm16 => _pcm16Controller.stream;

  @override
  Future<void> start() async {
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    _forwarding = true;
    _captureSub = stream.listen((frame) {
      if (_forwarding) _pcm16Controller.add(frame);
    });
  }

  @override
  Future<void> pause() async {
    _forwarding = false;
  }

  @override
  Future<void> resume() async {
    _forwarding = true;
  }

  @override
  Future<void> stop() async {
    await _captureSub?.cancel();
    _captureSub = null;
    await _recorder.stop();
  }

  /// Fully releases the underlying recorder. Distinct from [stop]: this
  /// instance can no longer be [start]ed again afterwards. Call this when
  /// tearing down the owning session, not on every turn.
  Future<void> dispose() async {
    await _captureSub?.cancel();
    _captureSub = null;
    await _recorder.dispose();
    await _pcm16Controller.close();
  }
}
