import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vocra_core/vocra_core.dart';

/// Implements [MicSource] via the optional native AEC module (spec §9,
/// T18): mono 16 kHz PCM16 capture with hardware echo cancellation, for use
/// with [DuplexMode.fullDuplex].
///
/// Check [isAvailable] before constructing a [VoiceConfig] with
/// [DuplexMode.fullDuplex] and this mic source — per the spec, half-duplex
/// with [FlutterMicSource] is the fallback when AEC isn't available, and
/// that fallback decision belongs to the app/`VoiceSession`, not this
/// class.
///
/// This talks to native Swift (`ios/Classes/AecAudioEngine.swift`) and
/// Kotlin (`android/.../AecAudioRecorder.kt`) code written against the
/// platforms' documented voice-processing APIs but not exercised on a
/// physical device as part of this build — the channel protocol and
/// Dart-side wiring are what's verified here; actual echo-cancellation
/// quality is unverified.
class NativeAecMicSource implements MicSource {
  static const MethodChannel _methodChannel = MethodChannel(
    'voice_flutter/aec_mic',
  );
  static const EventChannel _eventChannel = EventChannel(
    'voice_flutter/aec_mic/stream',
  );

  static Future<bool> isAvailable() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  StreamSubscription<dynamic>? _nativeSub;
  final StreamController<Uint8List> _pcm16Controller =
      StreamController<Uint8List>.broadcast();
  bool _forwarding = true;
  int _sampleRate = 16000;

  @override
  int get sampleRate => _sampleRate;

  @override
  Stream<Uint8List> get pcm16 => _pcm16Controller.stream;

  @override
  Future<void> start() async {
    final rate = await _methodChannel.invokeMethod<int>('sampleRate');
    if (rate != null) _sampleRate = rate;

    _forwarding = true;
    // Subscribe before calling 'start' — the native side requires a
    // listener attached to the event channel first (see
    // VoiceFlutterPlugin's "NO_LISTENER" error).
    _nativeSub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (!_forwarding) return;
      final bytes = event is Uint8List
          ? event
          : Uint8List.fromList(List<int>.from(event as List));
      _pcm16Controller.add(bytes);
    });

    await _methodChannel.invokeMethod<void>('start');
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
    await _methodChannel.invokeMethod<void>('stop');
    await _nativeSub?.cancel();
    _nativeSub = null;
  }

  /// Fully releases the channel subscription. Distinct from [stop]: call
  /// this when tearing down the owning session, not on every turn.
  Future<void> dispose() async {
    await stop();
    await _pcm16Controller.close();
  }
}
