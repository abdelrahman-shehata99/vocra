import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:voice_core/voice_core.dart';

/// Implements [AudioSink] via just_audio (spec §8.1): writes each clip to a
/// temp file and appends it to the player's playlist (via
/// [AudioPlayer.addAudioSource]) so playback continues without reloading
/// the player between clips.
///
/// [AudioQueue] (voice_core) only ever has one clip in flight — it waits for
/// [clipFinished] before calling [enqueue] again (spec §6.2's player-loop
/// design) — so this mainly buys continuous playback state (no reload/seek
/// gap, no re-acquiring the platform player) rather than true look-ahead
/// prefetching. Using a persistent playlist regardless keeps this correct
/// if AudioQueue is ever changed to pipeline clips ahead of time.
class FlutterAudioSink implements AudioSink {
  FlutterAudioSink({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _currentIndexSub = _player.currentIndexStream.listen(_onPlaybackProgressed);
    _processingStateSub = _player.processingStateStream.listen(
      (_) => _onPlaybackProgressed(_player.currentIndex),
    );
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  final AudioPlayer _player;
  bool _sourceAttached = false;

  /// Index of the last clip we've already reported via [clipFinished].
  /// Starts at -1 (none finished yet).
  int _lastFinishedIndex = -1;

  final List<File> _tempFiles = [];
  Directory? _tempDir;
  int _fileCounter = 0;

  late final StreamSubscription<int?> _currentIndexSub;
  late final StreamSubscription<ProcessingState> _processingStateSub;
  late final StreamSubscription<PlayerState> _playerStateSub;

  final StreamController<void> _clipFinishedController =
      StreamController<void>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  @override
  Stream<void> get clipFinished => _clipFinishedController.stream;

  @override
  Stream<double> get amplitude => _amplitudeController.stream;

  @override
  Future<void> enqueue(int index, Uint8List bytes, String format) async {
    final file = await _writeTempFile(bytes, format);
    final source = AudioSource.file(file.path);

    if (!_sourceAttached) {
      _sourceAttached = true;
      await _player.setAudioSource(source);
    } else {
      await _player.addAudioSource(source);
    }

    if (!_player.playing) {
      unawaited(_player.play());
    }
  }

  @override
  Future<void> stopNow() async {
    await _player.stop();
    if (_sourceAttached) {
      await _player.clearAudioSources();
    }
    _sourceAttached = false;
    _lastFinishedIndex = -1;
    await _deleteTempFiles();
  }

  @override
  Future<void> dispose() async {
    await _currentIndexSub.cancel();
    await _processingStateSub.cancel();
    await _playerStateSub.cancel();
    await _deleteTempFiles();
    await _player.dispose();
    await _clipFinishedController.close();
    await _amplitudeController.close();
  }

  /// Fires [clipFinished] for every playlist index that must have finished
  /// given the player's current position: every index strictly before
  /// [currentIndex] has necessarily played through, and if processing has
  /// reached [ProcessingState.completed] while sitting on [currentIndex],
  /// that one has finished too (there's nothing after it to advance to).
  void _onPlaybackProgressed(int? currentIndex) {
    if (currentIndex == null || _clipFinishedController.isClosed) return;

    final completed = _player.processingState == ProcessingState.completed;
    final finishedThrough = completed ? currentIndex : currentIndex - 1;

    while (_lastFinishedIndex < finishedThrough) {
      _lastFinishedIndex++;
      _clipFinishedController.add(null);
    }
  }

  void _onPlayerState(PlayerState state) {
    if (_amplitudeController.isClosed) return;
    // No cheap level-metering API in just_audio — fall back to the
    // documented "simple on/off envelope" (spec §8.1).
    _amplitudeController.add(state.playing ? 1.0 : 0.0);
  }

  Future<File> _writeTempFile(Uint8List bytes, String format) async {
    _tempDir ??= await Directory.systemTemp.createTemp('voice_flutter_tts_');
    final file = File('${_tempDir!.path}/clip_${_fileCounter++}.$format');
    await file.writeAsBytes(bytes, flush: true);
    _tempFiles.add(file);
    return file;
  }

  Future<void> _deleteTempFiles() async {
    final files = List<File>.of(_tempFiles);
    _tempFiles.clear();
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Best-effort cleanup — a locked/already-gone file isn't fatal.
      }
    }
  }
}
