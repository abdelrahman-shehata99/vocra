import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vocra/vocra.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(AudioSource.file('/tmp/fallback.mp3'));
  });

  group('FlutterAudioSink', () {
    late _MockAudioPlayer player;
    late StreamController<ProcessingState> processing;
    late StreamController<PlayerState> playerState;
    late FlutterAudioSink sink;

    setUp(() {
      player = _MockAudioPlayer();
      processing = StreamController<ProcessingState>.broadcast();
      playerState = StreamController<PlayerState>.broadcast();
      when(
        () => player.processingStateStream,
      ).thenAnswer((_) => processing.stream);
      when(
        () => player.playerStateStream,
      ).thenAnswer((_) => playerState.stream);
      when(() => player.setAudioSource(any())).thenAnswer((_) async => null);
      when(() => player.play()).thenAnswer((_) async {});
      when(() => player.stop()).thenAnswer((_) async {});
      when(() => player.dispose()).thenAnswer((_) async {});
      sink = FlutterAudioSink(player: player);
    });

    tearDown(() async {
      await processing.close();
      await playerState.close();
    });

    Future<void> enqueueOne() =>
        sink.enqueue(0, Uint8List.fromList([1, 2, 3]), 'mp3');

    test('reports clipFinished exactly once when a clip completes', () async {
      final finished = <void>[];
      sink.clipFinished.listen(finished.add);

      await enqueueOne();
      processing.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);
      // A stray second completed must not double-report.
      processing.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);

      expect(finished, hasLength(1));
    });

    test(
      'a clip that errors still advances the queue via clipFinished',
      () async {
        final finished = <void>[];
        sink.clipFinished.listen(finished.add);

        await enqueueOne();
        processing.addError(StateError('decode failed'));
        await Future<void>.delayed(Duration.zero);

        expect(finished, hasLength(1));
      },
    );

    test('stopNow does not emit a spurious clipFinished', () async {
      final finished = <void>[];
      sink.clipFinished.listen(finished.add);

      await enqueueOne();
      await sink.stopNow();
      await Future<void>.delayed(Duration.zero);

      expect(finished, isEmpty);
    });

    test('amplitude maps playing state to a 1/0 envelope', () async {
      final amplitudes = <double>[];
      sink.amplitude.listen(amplitudes.add);

      playerState.add(PlayerState(true, ProcessingState.ready));
      playerState.add(PlayerState(false, ProcessingState.ready));
      await Future<void>.delayed(Duration.zero);

      expect(amplitudes, [1.0, 0.0]);
    });
  });
}
