import 'dart:async';
import 'dart:typed_data';

import '../io/audio_sink.dart';

/// TTS for multiple sentences runs in parallel, but playback through
/// [AudioSink] is strictly ordered and instantly stoppable (spec §6.2).
///
/// Beyond the contract in the spec, this also exposes [completeTurn] and
/// [drained]: the spec's player loop description ("wait until a clip
/// appears or the turn ends") requires some signal for "the turn ends" —
/// the engine calls [completeTurn] once it has submitted the last sentence
/// of a turn (after the LLM stream ends and the splitter is flushed), and
/// [drained] fires once every submitted clip up to that point has finished
/// playing. The engine uses that to know when to resume the mic.
class AudioQueue {
  AudioQueue({required AudioSink sink, required String audioFormat})
    : _sink = sink,
      _audioFormat = audioFormat {
    _clipFinishedSub = _sink.clipFinished.listen((_) => _onClipFinished());
  }

  final AudioSink _sink;
  final String _audioFormat;
  late final StreamSubscription<void> _clipFinishedSub;

  int _epoch = 0;
  int get epoch => _epoch;

  int _nextToPlay = 0;
  int _submittedCount = 0;
  bool _turnComplete = false;
  bool _playingCurrent = false;

  final Map<int, Uint8List> _ready = {};

  /// Indices whose synthesis resolved with no playable audio (failed TTS, or
  /// an empty clip). The player loop must advance *past* these rather than
  /// wait on them forever — otherwise one failed sentence stalls the whole
  /// turn and the mic never resumes. Mirrors the HTML reference's
  /// `AudioQueue.skip()`.
  final Set<int> _skipped = {};

  final StreamController<void> _drainedController =
      StreamController<void>.broadcast();
  final StreamController<int> _clipStartedController =
      StreamController<int>.broadcast();

  /// Fires once all clips submitted before [completeTurn] have finished
  /// playing.
  Stream<void> get drained => _drainedController.stream;

  /// Fires the index each time a clip is actually handed to [AudioSink] to
  /// play — i.e. when it becomes audible, not just when its bytes are
  /// ready. The engine uses the first event per turn to know when to
  /// transition into [TurnState.speaking] and to record `timeToFirstVoice`.
  Stream<int> get clipStarted => _clipStartedController.stream;

  /// Resets indices and bumps the epoch for a new turn.
  void beginTurn() {
    _epoch++;
    _nextToPlay = 0;
    _submittedCount = 0;
    _turnComplete = false;
    _playingCurrent = false;
    _ready.clear();
    _skipped.clear();
  }

  /// Call once the last sentence of the current turn has been submitted.
  void completeTurn() {
    _turnComplete = true;
    _maybeEmitDrained();
  }

  /// Submits the (still-synthesizing) clip for [index]. When [clip]
  /// resolves, it is stored only if [epoch] still matches the queue's
  /// current epoch — a clip from a turn that was since interrupted is
  /// dropped on arrival.
  void submit(int index, Future<Uint8List> clip, int epoch) {
    _submittedCount++;
    clip.then(
      (bytes) {
        if (epoch != _epoch) return; // stale epoch — drop
        _ready[index] = bytes;
        _tryPlayNext();
      },
      // A failed synthesis (network error, 429, or cancelled mid-flight)
      // must not crash as an unhandled exception, and must not stall the
      // queue: mark the slot skipped so the player loop advances past it to
      // the remaining clips rather than waiting on an index that will never
      // arrive. A stale-epoch failure is simply dropped.
      onError: (Object _, StackTrace __) {
        if (epoch != _epoch) return;
        _skipped.add(index);
        _tryPlayNext();
      },
    );
  }

  /// Stops immediately, drops everything queued, and ignores late arrivals
  /// from before this call.
  Future<void> interrupt() async {
    _epoch++;
    _ready.clear();
    _skipped.clear();
    _playingCurrent = false;
    await _sink.stopNow();
  }

  Future<void> dispose() async {
    await _clipFinishedSub.cancel();
    await _drainedController.close();
    await _clipStartedController.close();
  }

  void _tryPlayNext() {
    if (_playingCurrent) return;

    // Advance past any slots that resolved with no audio (failed/skipped),
    // so a gap in the middle of a turn doesn't block the clips after it.
    while (_skipped.remove(_nextToPlay)) {
      _nextToPlay++;
    }

    final bytes = _ready[_nextToPlay];
    if (bytes == null) {
      _maybeEmitDrained();
      return;
    }

    _playingCurrent = true;
    _clipStartedController.add(_nextToPlay);
    unawaited(_sink.enqueue(_nextToPlay, bytes, _audioFormat));
  }

  void _onClipFinished() {
    if (!_playingCurrent) return; // stray event, ignore
    _ready.remove(_nextToPlay);
    _nextToPlay++;
    _playingCurrent = false;
    _tryPlayNext();
  }

  void _maybeEmitDrained() {
    if (_turnComplete && !_playingCurrent && _nextToPlay >= _submittedCount) {
      _drainedController.add(null);
    }
  }
}
