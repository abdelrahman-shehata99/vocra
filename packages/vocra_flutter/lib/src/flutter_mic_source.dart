import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:vocra_core/vocra_core.dart';

/// Implements [MicSource] via `record` (spec §8.2): streams mono PCM16
/// frames at 16 kHz.
///
/// [pause]/[resume] fully STOP and RESTART native capture rather than just
/// gating the stream. The spec suggested gating (keep capture open) to avoid
/// restart latency, but in practice on Android/the emulator, running the
/// recorder concurrently with the TTS playback puts the audio device into a
/// bad state — after the first reply the mic input goes silent (Deepgram
/// receives empty audio) and never recovers. Stopping the recorder while the
/// AI speaks guarantees recording and playback never overlap, which keeps
/// the mic healthy across turns. The restart costs ~100ms, paid only when
/// handing the turn back to the user — imperceptible in conversation.
class FlutterMicSource implements MicSource {
  FlutterMicSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  static const int _sampleRate = 16000;

  StreamSubscription<Uint8List>? _captureSub;
  // A single long-lived controller the engine subscribes to once. Restarting
  // capture swaps the inner subscription but keeps this controller, so the
  // engine's `pcm16` listener survives every pause/resume.
  final StreamController<Uint8List> _pcm16Controller =
      StreamController<Uint8List>.broadcast();

  bool _capturing = false;

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: _sampleRate,
    numChannels: 1,
    // We stop the recorder during the AI's turn, so it never needs to react
    // to the playback interruption itself.
    audioInterruption: AudioInterruptionMode.none,
  );

  @override
  int get sampleRate => _sampleRate;

  @override
  Stream<Uint8List> get pcm16 => _pcm16Controller.stream;

  @override
  Future<void> start() async {
    // ignore: avoid_print
    print('[vocra] FlutterMicSource.start: hasPermission check...');
    final has = await _recorder.hasPermission();
    // ignore: avoid_print
    print('[vocra] FlutterMicSource.start: hasPermission=$has');
    await _startCapture();
  }

  Future<void> _startCapture() async {
    if (_capturing) return;
    // ignore: avoid_print
    print('[vocra] FlutterMicSource: startStream...');
    final stream = await _recorder.startStream(_config);
    _capturing = true;
    // ignore: avoid_print
    print('[vocra] FlutterMicSource: capturing');
    _captureSub = stream.listen(
      (frame) => _pcm16Controller.add(frame),
      onError: (Object e) {
        // ignore: avoid_print
        print('[vocra] FlutterMicSource: capture stream error: $e');
      },
      onDone: () {
        // ignore: avoid_print
        print('[vocra] FlutterMicSource: capture stream DONE');
      },
    );
  }

  Future<void> _stopCapture() async {
    if (!_capturing) return;
    _capturing = false;
    await _captureSub?.cancel();
    _captureSub = null;
    await _recorder.stop();
  }

  /// Half-duplex: called when the AI starts speaking. Fully stops native
  /// capture so it never runs concurrently with TTS playback.
  @override
  Future<void> pause() async {
    // ignore: avoid_print
    print('[vocra] FlutterMicSource.pause: stopping capture (AI speaking)');
    await _stopCapture();
  }

  /// Called when the AI stops speaking. Starts a fresh recording.
  @override
  Future<void> resume() async {
    // ignore: avoid_print
    print('[vocra] FlutterMicSource.resume: restarting capture');
    await _startCapture();
  }

  @override
  Future<void> stop() async {
    await _stopCapture();
  }

  /// Fully releases the underlying recorder. Distinct from [stop]: this
  /// instance can no longer be [start]ed again afterwards. Call this when
  /// tearing down the owning session, not on every turn.
  Future<void> dispose() async {
    await _stopCapture();
    await _recorder.dispose();
    await _pcm16Controller.close();
  }
}
