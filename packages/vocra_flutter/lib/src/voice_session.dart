import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:vocra_core/vocra_core.dart';

import 'audio_session_setup.dart';
import 'flutter_audio_sink.dart';
import 'flutter_mic_source.dart';
import 'mic_permission.dart';
import 'native_aec_mic_source.dart';

/// The single app-facing class consuming apps use (spec §8.6). Constructs
/// the concrete Flutter implementations and a [VoiceEngine], runs
/// permission + audio-session setup, and re-exposes the engine's streams
/// and methods.
class VoiceSession {
  VoiceSession({required VoiceConfig config})
    : _config = config,
      _mic = config.duplex == DuplexMode.fullDuplex
          ? NativeAecMicSource()
          : FlutterMicSource(),
      _sink = FlutterAudioSink(),
      _micPermission = const MicPermission() {
    _engine = VoiceEngine(config, audioSink: _sink, mic: _mic);
    _engineErrorsSub = _engine.errors.listen(_errorsController.add);
  }

  final VoiceConfig _config;
  final MicSource _mic;
  final FlutterAudioSink _sink;
  final MicPermission _micPermission;
  late final VoiceEngine _engine;
  late final StreamSubscription<VoiceError> _engineErrorsSub;

  final StreamController<VoiceError> _errorsController =
      StreamController<VoiceError>.broadcast();

  AudioSessionSetup? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  bool _started = false;
  bool _starting = false;
  bool _stopping = false;

  Stream<TurnState> get turnState => _engine.turnState;
  Stream<TranscriptEvent> get transcripts => _engine.transcripts;
  Stream<TurnMetrics> get metrics => _engine.metrics;

  /// Engine errors plus session-level errors (e.g. permission denial) that
  /// have no equivalent in [VoiceEngine] itself.
  Stream<VoiceError> get errors => _errorsController.stream;

  Future<void> requestPermissions() async {
    await _micPermission.request();
  }

  /// Permissions + audio session setup + `engine.startConversation()`. If
  /// the mic permission isn't granted, this emits a [ConfigError] on
  /// [errors] and returns without starting — it does not throw, so a UI
  /// driven entirely by these streams doesn't need a try/catch here.
  ///
  /// [_starting] is set synchronously (before any `await`) so two rapid
  /// calls — e.g. a double-tapped mic button — can't both slip past the
  /// `_started` guard and start the conversation twice concurrently.
  Future<void> start() async {
    // ignore: avoid_print
    print('[vocra] VoiceSession.start() called (duplex=${_config.duplex})');
    if (_started || _starting) return;
    _starting = true;
    try {
      if (_config.duplex == DuplexMode.fullDuplex &&
          !await NativeAecMicSource.isAvailable()) {
        _errorsController.add(
          const ConfigError(
            'Full-duplex requires native echo cancellation, which is not '
            'available on this build/device. Use DuplexMode.halfDuplex instead.',
          ),
        );
        return;
      }

      // ignore: avoid_print
      print('[vocra] requesting mic permission...');
      final status = await _micPermission.request();
      // ignore: avoid_print
      print('[vocra] mic permission status = $status');
      if (status != MicPermissionStatus.granted) {
        _errorsController.add(
          const ConfigError('Microphone permission was not granted.'),
        );
        return;
      }

      // ignore: avoid_print
      print('[vocra] configuring audio session...');
      final audioSession = await AudioSessionSetup.configure();
      _audioSession = audioSession;
      _wireAudioSessionReactions(audioSession);

      // ignore: avoid_print
      print('[vocra] audio session ok; calling engine.startConversation()...');
      await _engine.startConversation();
      _started = true;
      // ignore: avoid_print
      print('[vocra] VoiceSession.start() COMPLETE, _started=true');
    } catch (e, st) {
      // ignore: avoid_print
      print('[vocra] VoiceSession.start() THREW: $e\n$st');
      _errorsController.add(
        e is VoiceError ? e : NetworkError('start() failed: $e'),
      );
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    if (!_started || _stopping) return;
    _stopping = true;
    try {
      await _interruptionSub?.cancel();
      _interruptionSub = null;
      await _becomingNoisySub?.cancel();
      _becomingNoisySub = null;

      await _engine.stopConversation();
      await _audioSession?.setActive(false);
    } catch (e) {
      _errorsController.add(
        e is VoiceError ? e : NetworkError('stop() failed: $e'),
      );
    } finally {
      // Even a failed teardown must not brick the session: start()
      // reconfigures everything from scratch, so always clear the guard —
      // otherwise one bad stop() would make every later start() a no-op
      // and the mic button would appear permanently dead.
      _started = false;
      _stopping = false;
    }
  }

  Future<void> sendText(String text) => _engine.sendText(text);

  /// Speaks [text] in the assistant's voice without an LLM call — for
  /// notifications, tutorial prompts, or scripted interjections. The text is
  /// recorded on [transcripts] and in history like any reply; a call while a
  /// turn is already in flight is dropped.
  Future<void> speak(String text) => _engine.speak(text);

  Future<void> dispose() async {
    await stop();
    await _engineErrorsSub.cancel();
    await _errorsController.close();
    await _engine.dispose();
    await _disposeMic();
    await _sink.dispose();
  }

  /// [MicSource] doesn't declare a `dispose()` (only [stop], which leaves
  /// the underlying recorder/engine reusable for another `start()`) — both
  /// concrete implementations add their own for full teardown.
  Future<void> _disposeMic() async {
    final mic = _mic;
    if (mic is FlutterMicSource) {
      await mic.dispose();
    } else if (mic is NativeAecMicSource) {
      await mic.dispose();
    }
  }

  void _wireAudioSessionReactions(AudioSessionSetup audioSession) {
    // A phone call (or other app) taking audio focus: cut the current turn
    // and drop back to listening rather than continuing to talk over it.
    _interruptionSub = audioSession.interruptions.listen((event) {
      if (event.begin) {
        unawaited(_engine.interrupt());
      }
    });

    // Headphones/AirPods unplugged: don't let playback suddenly blast out
    // of the speaker.
    _becomingNoisySub = audioSession.becomingNoisy.listen((_) {
      unawaited(_engine.interrupt());
    });
  }
}
