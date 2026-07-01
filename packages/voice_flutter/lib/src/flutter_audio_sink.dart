import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:voice_core/voice_core.dart';

/// Implements [AudioSink] via just_audio (spec §8.1).
///
/// [AudioQueue] (voice_core) only ever has one clip in flight — it waits for
/// [clipFinished] before submitting the next (spec §6.2's player-loop
/// design). We lean on that guarantee and play each clip as its own single
/// source ([AudioPlayer.setAudioSource] + [AudioPlayer.play]), reporting
/// [clipFinished] when the player reaches [ProcessingState.completed].
///
/// Why not a growing playlist (as the spec sketches for gaplessness): because
/// clips are submitted strictly one-at-a-time *after* the previous finished,
/// the player has almost always already reached `completed` by the time the
/// next clip arrives — and appending to an already-completed just_audio
/// player does not reliably resume playback, which strands every clip after
/// the first. A per-clip source sidesteps that entirely; the only cost is a
/// small file-load gap between sentences (imperceptible in practice, and no
/// worse than the serialized submission already implies).
class FlutterAudioSink implements AudioSink {
  FlutterAudioSink({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _processingStateSub = _player.processingStateStream.listen(
      _onProcessingState,
      // A clip that fails to load/decode surfaces as a stream error. Treat it
      // as finished so AudioQueue advances to the next sentence instead of
      // hanging forever on a clip that will never reach `completed`.
      onError: (Object _, StackTrace __) => _reportClipDone(),
    );
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  final AudioPlayer _player;

  /// True between handing a clip to the player and observing it complete.
  /// Guards [clipFinished] so the `completed` state is reported exactly once
  /// per clip, and never spuriously (e.g. a `stopNow` doesn't emit
  /// `completed`, and `setAudioSource` transitions through `loading`/`ready`,
  /// not `completed`).
  bool _awaitingClip = false;

  final List<File> _tempFiles = [];
  Directory? _tempDir;
  int _fileCounter = 0;

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
    // Set the guard before loading the source so the *next* `completed` we
    // see is unambiguously this clip finishing.
    _awaitingClip = true;
    await _player.setAudioSource(AudioSource.file(file.path));
    // Not awaited: play() resolves only when the clip finishes, and letting
    // its rejection escape an unawaited enqueue would surface as an unhandled
    // async error. Completion is reported via processingStateStream instead.
    unawaited(_player.play());
  }

  @override
  Future<void> stopNow() async {
    _awaitingClip = false;
    await _player.stop();
    await _deleteTempFiles();
  }

  @override
  Future<void> dispose() async {
    _awaitingClip = false;
    await _processingStateSub.cancel();
    await _playerStateSub.cancel();
    await _deleteTempFiles();
    await _player.dispose();
    await _clipFinishedController.close();
    await _amplitudeController.close();
  }

  void _onProcessingState(ProcessingState state) {
    if (state == ProcessingState.completed) _reportClipDone();
  }

  /// Reports the in-flight clip as finished exactly once (clearing the guard
  /// first), whether it completed normally or errored out. A no-op if no clip
  /// is awaiting, so stray events can't fire a spurious [clipFinished].
  void _reportClipDone() {
    if (_clipFinishedController.isClosed || !_awaitingClip) return;
    _awaitingClip = false;
    _clipFinishedController.add(null);
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
