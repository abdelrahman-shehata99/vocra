import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

import 'fakes.dart';

Future<void> pump([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Harness {
  _Harness({
    int maxHistoryMessages = 20,
    DuplexMode duplex = DuplexMode.halfDuplex,
    BargeInSensitivity sensitivity = BargeInSensitivity.balanced,
  }) : mic = FakeMicSource(),
       stt = FakeSttTransport(),
       llm = FakeLlmProvider(),
       tts = FakeTtsProvider(),
       sink = FakeAudioSink() {
    config = VoiceConfig(
      llm: llm,
      tts: tts,
      stt: stt,
      systemPrompt: 'You are a helpful assistant.',
      maxHistoryMessages: maxHistoryMessages,
      duplex: duplex,
      sensitivity: sensitivity,
    );
    engine = VoiceEngine(config, audioSink: sink, mic: mic);
  }

  final FakeMicSource mic;
  final FakeSttTransport stt;
  final FakeLlmProvider llm;
  final FakeTtsProvider tts;
  final FakeAudioSink sink;
  late final VoiceConfig config;
  late final VoiceEngine engine;
}

void main() {
  group('VoiceEngine', () {
    test(
      'full turn: listening -> thinking -> speaking -> listening, with metrics and history growth',
      () async {
        final h = _Harness();
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);
        final metricsList = <TurnMetrics>[];
        h.engine.metrics.listen(metricsList.add);
        final transcriptEvents = <TranscriptEvent>[];
        h.engine.transcripts.listen(transcriptEvents.add);

        await h.engine.startConversation();
        await pump();
        expect(states, [TurnState.listening]);
        expect(h.mic.started, isTrue);
        expect(h.stt.started, isTrue);

        h.stt.emitFinal('hello there');
        await pump(5);

        h.llm.pushToken('Hi there! ');
        h.llm.pushToken('How can I help today? ');
        await h.llm.endStream();
        await pump(30);

        expect(states, [
          TurnState.listening,
          TurnState.thinking,
          TurnState.speaking,
          TurnState.listening,
        ]);

        expect(h.mic.pauseCalls, 1);
        expect(h.mic.resumeCalls, 1);

        // History: system, user, assistant.
        expect(h.llm.historySnapshots, hasLength(1));
        final history = h.llm.historySnapshots.single;
        expect(
          history,
          hasLength(2),
        ); // system + user (assistant not yet appended at call time)
        expect(history[0].role, MessageRole.system);
        expect(history[1].role, MessageRole.user);
        expect(history[1].content, 'hello there');

        expect(
          transcriptEvents.any((e) => e.source == TranscriptSource.assistant),
          isTrue,
        );

        expect(metricsList, hasLength(1));
        final m = metricsList.single;
        expect(m.ttft, isNotNull);
        expect(m.firstSentenceReady, isNotNull);
        expect(m.firstTtsReady, isNotNull);
        expect(m.timeToFirstVoice, isNotNull);
        expect(m.total, isNotNull);
      },
    );

    test(
      'mic audio is never forwarded to STT while thinking or speaking (R7)',
      () async {
        final h = _Harness();
        final speakingReached = Completer<void>();
        h.engine.turnState.listen((s) {
          if (s == TurnState.speaking && !speakingReached.isCompleted) {
            speakingReached.complete();
          }
        });

        await h.engine.startConversation();

        final whileListening = Uint8List.fromList([1]);
        h.mic.emit(whileListening);
        await pump(3);
        expect(h.stt.sentAudio, [whileListening]);

        h.stt.emitFinal('go');
        await pump(5); // now thinking

        final whileThinking = Uint8List.fromList([2]);
        h.mic.emit(whileThinking);
        await pump(3);

        h.llm.pushToken('Hello there! ');
        await speakingReached.future.timeout(const Duration(seconds: 2));

        final whileSpeaking = Uint8List.fromList([3]);
        h.mic.emit(whileSpeaking);
        await pump(3);

        await h.llm.endStream();
        await pump(30);

        // Only the pre-turn frame ever reached STT.
        expect(h.stt.sentAudio, [whileListening]);

        final afterTurn = Uint8List.fromList([4]);
        h.mic.emit(afterTurn);
        await pump(3);
        expect(h.stt.sentAudio, [whileListening, afterTurn]);
      },
    );

    test('sendText starts a turn directly, bypassing STT', () async {
      final h = _Harness();
      await h.engine.startConversation();

      unawaited(h.engine.sendText('typed message'));
      await pump(3);

      expect(h.llm.historySnapshots, hasLength(1));
      expect(h.llm.historySnapshots.single.last.content, 'typed message');
      expect(h.stt.sentAudio, isEmpty);

      h.llm.pushToken('Sure! ');
      await h.llm.endStream();
      await pump(30);
    });

    test(
      'typed input works with no mic conversation and rests at idle',
      () async {
        final h = _Harness();
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);

        // No startConversation() — pure typed usage.
        unawaited(h.engine.sendText('hello there'));
        await pump(5);

        h.llm.pushToken('Hi! How can I help? ');
        await h.llm.endStream();
        await pump(30);

        // Ran a full turn straight from idle and settled back at idle.
        expect(states, [
          TurnState.thinking,
          TurnState.speaking,
          TurnState.idle,
        ]);
        // No mic was ever started/paused/resumed.
        expect(h.mic.started, isFalse);
        expect(h.mic.pauseCalls, 0);
        expect(h.mic.resumeCalls, 0);
        // The assistant reply made it into history.
        expect(
          h.llm.historySnapshots.last.where((m) => m.role == MessageRole.user),
          isNotEmpty,
        );
      },
    );

    test(
      'interrupt() cancels the in-flight turn and returns to listening',
      () async {
        final h = _Harness();
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);

        await h.engine.startConversation();
        h.stt.emitFinal('go');
        await pump(5);

        h.llm.pushToken('Hello ');
        await pump(5);

        await h.engine.interrupt();
        await pump(5);

        expect(h.llm.lastCancel?.isCancelled, isTrue);
        expect(states.last, TurnState.listening);
        expect(h.mic.resumeCalls, greaterThanOrEqualTo(1));
      },
    );

    test(
      'history trims oldest non-system messages, keeping the system prompt',
      () async {
        final h = _Harness(maxHistoryMessages: 3);
        await h.engine.startConversation();

        Future<void> runTurn(String userText, String replyToken) async {
          h.stt.emitFinal(userText);
          await pump(5);
          h.llm.pushToken(replyToken);
          await h.llm.endStream();
          await pump(30);
        }

        await runTurn('one', 'Reply one! ');
        await runTurn('two', 'Reply two! ');

        final lastHistory = h.llm.historySnapshots.last;
        expect(lastHistory.length, lessThanOrEqualTo(3));
        expect(lastHistory.first.role, MessageRole.system);
        expect(lastHistory.first.content, 'You are a helpful assistant.');
      },
    );

    test(
      'an LLM error is surfaced on errors and the engine returns to listening',
      () async {
        final h = _Harness();
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);
        final errors = <VoiceError>[];
        h.engine.errors.listen(errors.add);

        await h.engine.startConversation();
        h.stt.emitFinal('go');
        await pump(5);

        h.llm.failWith(const NetworkError());
        await pump(10);

        expect(errors, [isA<NetworkError>()]);
        expect(states.last, TurnState.listening);
      },
    );

    test('a dropped STT connection is surfaced on errors', () async {
      final h = _Harness();
      final errors = <VoiceError>[];
      h.engine.errors.listen(errors.add);

      await h.engine.startConversation();
      h.stt.emitConnectionError(
        const NetworkError('Deepgram STT connection lost.'),
      );
      await pump(5);

      expect(errors, [isA<NetworkError>()]);
    });

    test('stopConversation tears everything down and goes idle', () async {
      final h = _Harness();
      final states = <TurnState>[];
      h.engine.turnState.listen(states.add);

      await h.engine.startConversation();
      await h.engine.stopConversation();
      await pump(3);

      expect(states.last, TurnState.idle);
      expect(h.mic.stopCalls, 1);
      expect(h.stt.stopped, isTrue);
    });

    test(
      'a failed TTS clip does not hang the turn: it still drains and resumes',
      () async {
        final h = _Harness();
        // Second sentence's synthesis fails (e.g. a 429); the first and
        // third succeed. The turn must still complete and return to
        // listening rather than stalling in speaking forever.
        h.tts.handler = (text) async {
          if (text.contains('TWO')) {
            throw const RateLimitError();
          }
          return Uint8List.fromList(text.codeUnits);
        };
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);
        final errors = <VoiceError>[];
        h.engine.errors.listen(errors.add);

        await h.engine.startConversation();
        h.stt.emitFinal('go');
        await pump(5);

        h.llm.pushToken('Sentence ONE here. ');
        h.llm.pushToken('Sentence TWO here. ');
        h.llm.pushToken('Sentence THREE here. ');
        await h.llm.endStream();
        await pump(40);

        // Clips 1 and 3 played; clip 2 was skipped, not blocking.
        expect(h.sink.enqueuedIndexes, [0, 2]);
        // The rate-limit error from the failed clip was surfaced.
        expect(errors.whereType<RateLimitError>(), isNotEmpty);
        // Crucially: the turn finished and the mic came back.
        expect(states.last, TurnState.listening);
        expect(h.mic.resumeCalls, greaterThanOrEqualTo(1));
      },
    );
  });

  group('VoiceEngine full-duplex (spec §9)', () {
    test('never pauses the mic, unlike half-duplex', () async {
      final h = _Harness(duplex: DuplexMode.fullDuplex);

      await h.engine.startConversation();
      h.stt.emitFinal('go');
      await pump(5);

      h.llm.pushToken('Hello there! ');
      await pump(10);
      await h.llm.endStream();
      await pump(30);

      expect(h.mic.pauseCalls, 0);
      expect(h.mic.resumeCalls, 0);
    });

    test('mic audio keeps reaching STT while the AI is speaking', () async {
      final h = _Harness(duplex: DuplexMode.fullDuplex);
      final speakingReached = Completer<void>();
      h.engine.turnState.listen((s) {
        if (s == TurnState.speaking && !speakingReached.isCompleted) {
          speakingReached.complete();
        }
      });

      await h.engine.startConversation();
      h.stt.emitFinal('go');
      await pump(5);

      h.llm.pushToken('Hello there! ');
      await speakingReached.future.timeout(const Duration(seconds: 2));

      final whileSpeaking = Uint8List.fromList([7]);
      h.mic.emit(whileSpeaking);
      await pump(3);

      expect(h.stt.sentAudio, contains(whileSpeaking));
    });

    test(
      'a long interim transcript while speaking triggers a barge-in interrupt',
      () async {
        final h = _Harness(
          duplex: DuplexMode.fullDuplex,
          sensitivity: BargeInSensitivity.balanced, // threshold: 12 chars
        );
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);
        final speakingReached = Completer<void>();
        h.engine.turnState.listen((s) {
          if (s == TurnState.speaking && !speakingReached.isCompleted) {
            speakingReached.complete();
          }
        });

        await h.engine.startConversation();
        h.stt.emitFinal('go');
        await pump(5);

        h.llm.pushToken('Hello there, how can I help you today! ');
        await speakingReached.future.timeout(const Duration(seconds: 2));

        h.stt.emitInterim('wait stop'); // 9 chars — below the threshold
        await pump(5);
        expect(states.last, TurnState.speaking);

        h.stt.emitInterim('wait stop please'); // 16 chars — crosses it
        await pump(5);

        expect(states.last, TurnState.listening);
        expect(h.llm.lastCancel?.isCancelled, isTrue);
      },
    );

    test(
      'a short interim transcript while speaking does not interrupt',
      () async {
        final h = _Harness(
          duplex: DuplexMode.fullDuplex,
          sensitivity: BargeInSensitivity.relaxed, // threshold: 20 chars
        );
        final speakingReached = Completer<void>();
        h.engine.turnState.listen((s) {
          if (s == TurnState.speaking && !speakingReached.isCompleted) {
            speakingReached.complete();
          }
        });

        await h.engine.startConversation();
        h.stt.emitFinal('go');
        await pump(5);

        h.llm.pushToken('Hello there, how can I help you today! ');
        await speakingReached.future.timeout(const Duration(seconds: 2));

        h.stt.emitInterim('hmm ok'); // well under 20 chars
        await pump(5);

        expect(h.llm.lastCancel?.isCancelled, isFalse);
      },
    );
  });
}
