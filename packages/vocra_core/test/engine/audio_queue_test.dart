import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

/// A controllable fake [AudioSink]: `enqueue` records the call and waits
/// for the test to call [finishClip] before emitting `clipFinished`, so
/// tests can assert ordering deterministically instead of racing real I/O.
class FakeAudioSink implements AudioSink {
  final List<int> enqueuedIndexes = [];
  int stopNowCalls = 0;

  final StreamController<void> _clipFinishedController =
      StreamController<void>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  @override
  Future<void> enqueue(int index, Uint8List bytes, String format) async {
    enqueuedIndexes.add(index);
  }

  void finishClip() => _clipFinishedController.add(null);

  @override
  Future<void> stopNow() async {
    stopNowCalls++;
  }

  @override
  Stream<double> get amplitude => _amplitudeController.stream;

  @override
  Stream<void> get clipFinished => _clipFinishedController.stream;

  @override
  Future<void> dispose() async {
    await _clipFinishedController.close();
    await _amplitudeController.close();
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('AudioQueue', () {
    late FakeAudioSink sink;
    late AudioQueue queue;

    setUp(() {
      sink = FakeAudioSink();
      queue = AudioQueue(sink: sink, audioFormat: 'mp3');
    });

    tearDown(() async {
      await queue.dispose();
      await sink.dispose();
    });

    test('plays clips in order even when they resolve out of order', () async {
      queue.beginTurn();
      final epoch = queue.epoch;

      final c0 = Completer<Uint8List>();
      final c1 = Completer<Uint8List>();
      final c2 = Completer<Uint8List>();

      queue.submit(0, c0.future, epoch);
      queue.submit(1, c1.future, epoch);
      queue.submit(2, c2.future, epoch);
      queue.completeTurn();

      // Resolve out of order: 2, then 0, then 1.
      c2.complete(Uint8List.fromList([2]));
      await pump();
      expect(sink.enqueuedIndexes, isEmpty); // waiting on index 0

      c0.complete(Uint8List.fromList([0]));
      await pump();
      expect(sink.enqueuedIndexes, [0]);

      sink.finishClip(); // index 0 finished -> should immediately play 1? no, 1 not ready
      await pump();
      expect(sink.enqueuedIndexes, [0]); // still waiting on index 1

      c1.complete(Uint8List.fromList([1]));
      await pump();
      expect(sink.enqueuedIndexes, [0, 1]);

      sink.finishClip(); // index 1 finished -> index 2 already ready
      await pump();
      expect(sink.enqueuedIndexes, [0, 1, 2]);

      sink.finishClip(); // index 2 finished -> turn drained
      final drainedFuture = queue.drained.first;
      await pump();
      await expectLater(drainedFuture, completes);
    });

    test('interrupt drops pending clips and bumps the epoch', () async {
      queue.beginTurn();
      final epoch = queue.epoch;

      final c0 = Completer<Uint8List>();
      final c1 = Completer<Uint8List>();
      queue.submit(0, c0.future, epoch);
      queue.submit(1, c1.future, epoch);

      c0.complete(Uint8List.fromList([0]));
      await pump();
      expect(sink.enqueuedIndexes, [0]);

      await queue.interrupt();
      expect(sink.stopNowCalls, 1);
      expect(queue.epoch, epoch + 1);

      // index 1 resolves after the interrupt — must be dropped, not played.
      c1.complete(Uint8List.fromList([1]));
      await pump();
      expect(sink.enqueuedIndexes, [0]);
    });

    test('a clip resolving with a stale epoch is ignored on arrival', () async {
      queue.beginTurn();
      final staleEpoch = queue.epoch;

      final stale = Completer<Uint8List>();
      queue.submit(0, stale.future, staleEpoch);

      // A new turn begins (e.g. user interrupted and started a new turn)
      // before the stale clip resolves.
      queue.beginTurn();
      final currentEpoch = queue.epoch;
      expect(currentEpoch, isNot(staleEpoch));

      final fresh = Completer<Uint8List>();
      queue.submit(0, fresh.future, currentEpoch);

      stale.complete(Uint8List.fromList([99])); // resolves with old epoch
      await pump();
      expect(sink.enqueuedIndexes, isEmpty); // stale clip must not play

      fresh.complete(Uint8List.fromList([1]));
      await pump();
      expect(sink.enqueuedIndexes, [0]); // only the fresh clip played
    });

    test(
      'drained fires only after completeTurn and all clips finished',
      () async {
        queue.beginTurn();
        final epoch = queue.epoch;
        final c0 = Completer<Uint8List>();
        queue.submit(0, c0.future, epoch);

        var drainedCount = 0;
        queue.drained.listen((_) => drainedCount++);

        c0.complete(Uint8List.fromList([0]));
        await pump();
        sink.finishClip();
        await pump();
        expect(drainedCount, 0); // completeTurn() not called yet

        queue.completeTurn();
        await pump();
        expect(drainedCount, 1);
      },
    );

    test(
      'a failed clip is skipped so the queue plays the surviving clips',
      () async {
        queue.beginTurn();
        final epoch = queue.epoch;

        final failing = Completer<Uint8List>();
        final c1 = Completer<Uint8List>();
        queue.submit(0, failing.future, epoch);
        queue.submit(1, c1.future, epoch);

        failing.completeError(Exception('synthesis failed'));
        await pump();
        // index 0 failed — but index 1 must still play (queue advances past
        // the gap rather than stalling forever).
        c1.complete(Uint8List.fromList([1]));
        await pump();
        expect(sink.enqueuedIndexes, [1]);
      },
    );

    test(
      'a failed clip in the middle still lets the turn drain and resume',
      () async {
        queue.beginTurn();
        final epoch = queue.epoch;
        var drained = false;
        queue.drained.listen((_) => drained = true);

        final c0 = Completer<Uint8List>();
        final failing = Completer<Uint8List>();
        final c2 = Completer<Uint8List>();
        queue.submit(0, c0.future, epoch);
        queue.submit(1, failing.future, epoch);
        queue.submit(2, c2.future, epoch);
        queue.completeTurn();

        c0.complete(Uint8List.fromList([0]));
        failing.completeError(Exception('mid-turn TTS failure'));
        c2.complete(Uint8List.fromList([2]));
        await pump();

        // 0 plays first.
        expect(sink.enqueuedIndexes, [0]);
        sink.finishClip(); // 0 done -> skip 1 -> play 2
        await pump();
        expect(sink.enqueuedIndexes, [0, 2]);
        sink.finishClip(); // 2 done -> turn drains
        await pump();
        expect(drained, isTrue);
      },
    );

    test(
      'clipStarted fires the index when a clip is handed to the sink',
      () async {
        queue.beginTurn();
        final epoch = queue.epoch;
        final started = <int>[];
        queue.clipStarted.listen(started.add);

        final c0 = Completer<Uint8List>();
        final c1 = Completer<Uint8List>();
        queue.submit(0, c0.future, epoch);
        queue.submit(1, c1.future, epoch);

        c0.complete(Uint8List.fromList([0]));
        await pump();
        expect(started, [0]);

        sink.finishClip();
        c1.complete(Uint8List.fromList([1]));
        await pump();
        expect(started, [0, 1]);
      },
    );
  });
}
