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
    Greeting? greeting,
    bool naturalSpeech = false,
    String systemPrompt = 'You are a helpful assistant.',
    bool ttsSupportsAudioTags = false,
  }) : mic = FakeMicSource(),
       stt = FakeSttTransport(),
       llm = FakeLlmProvider(),
       tts = FakeTtsProvider(),
       sink = FakeAudioSink() {
    tts.supportsAudioTags = ttsSupportsAudioTags;
    config = VoiceConfig(
      llm: llm,
      tts: tts,
      stt: stt,
      systemPrompt: systemPrompt,
      maxHistoryMessages: maxHistoryMessages,
      duplex: duplex,
      sensitivity: sensitivity,
      greeting: greeting,
      naturalSpeech: naturalSpeech,
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
      final userEvents = <TranscriptEvent>[];
      h.engine.transcripts.listen((e) {
        if (e.source == TranscriptSource.user) userEvents.add(e);
      });
      await h.engine.startConversation();

      unawaited(h.engine.sendText('typed message'));
      await pump(3);

      // Typed input still appears on the transcript stream (it has no STT
      // leg to emit it), so the stream is the full conversation record.
      expect(userEvents, hasLength(1));
      expect(userEvents.single.text, 'typed message');
      expect(userEvents.single.isFinal, isTrue);

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

    test(
      'assistant text streams as cumulative interim transcripts (word-by-word '
      'UI rendering), then one final with the complete text',
      () async {
        final h = _Harness();
        final assistantEvents = <TranscriptEvent>[];
        h.engine.transcripts.listen((e) {
          if (e.source == TranscriptSource.assistant) assistantEvents.add(e);
        });

        await h.engine.startConversation();
        await pump();
        h.stt.emitFinal('hi');
        await pump(5);

        h.llm.pushToken('Hello ');
        await pump();
        h.llm.pushToken('world. ');
        await h.llm.endStream();
        await pump(30);

        final interims = assistantEvents.where((e) => !e.isFinal).toList();
        expect(
          interims.map((e) => e.text),
          ['Hello ', 'Hello world. '],
          reason: 'each token appends to a cumulative interim',
        );
        final finals = assistantEvents.where((e) => e.isFinal).toList();
        expect(finals, hasLength(1));
        expect(finals.single.text, 'Hello world. ');
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

  group('VoiceEngine greeting', () {
    test(
      'Greeting.text speaks first: thinking -> speaking -> listening before '
      'any user input, and the text reaches TTS',
      () async {
        final h = _Harness(greeting: const Greeting.text('Hey there!'));
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);

        await h.engine.startConversation();
        await pump(30);

        expect(states, [
          TurnState.listening,
          TurnState.thinking,
          TurnState.speaking,
          TurnState.listening,
        ]);
        expect(h.tts.synthesizedText, contains('Hey there!'));
        // The LLM is never called for a fixed-text greeting.
        expect(h.llm.historySnapshots, isEmpty);
      },
    );

    test(
      'Greeting.text emits assistant transcripts and appends the greeting to '
      'history as an assistant message',
      () async {
        final h = _Harness(greeting: const Greeting.text('Hey there!'));
        final transcripts = <TranscriptEvent>[];
        h.engine.transcripts.listen(transcripts.add);

        await h.engine.startConversation();
        await pump(30);

        expect(
          transcripts.any(
            (e) =>
                e.source == TranscriptSource.assistant &&
                e.isFinal &&
                e.text == 'Hey there!',
          ),
          isTrue,
        );

        // A following user turn should see the greeting in history as an
        // assistant message preceding the new user message.
        h.stt.emitFinal('hello');
        await pump(5);
        final history = h.llm.historySnapshots.single;
        expect(history[0].role, MessageRole.system);
        expect(history[1].role, MessageRole.assistant);
        expect(history[1].content, 'Hey there!');
        expect(history[2].role, MessageRole.user);
        expect(history[2].content, 'hello');
      },
    );

    test('Greeting.text pauses the mic while greeting, then resumes '
        '(half-duplex R7)', () async {
      final h = _Harness(greeting: const Greeting.text('Hey there!'));

      await h.engine.startConversation();
      await pump(30);

      expect(h.mic.pauseCalls, 1);
      expect(h.mic.resumeCalls, 1);
    });

    test(
      'Greeting.generated sends an ephemeral user instruction that is never '
      'stored in history',
      () async {
        final h = _Harness(greeting: const Greeting.generated());

        await h.engine.startConversation();
        await pump(5);

        // The generated greeting calls the LLM with [system, user(instruction)].
        final promptHistory = h.llm.historySnapshots.single;
        expect(promptHistory, hasLength(2));
        expect(promptHistory[0].role, MessageRole.system);
        expect(promptHistory[1].role, MessageRole.user);
        expect(promptHistory[1].content, contains('Greet the user'));

        h.llm.pushToken('Hello and welcome! ');
        await h.llm.endStream();
        await pump(30);

        // A following user turn must NOT contain the ephemeral instruction;
        // it should contain the stored assistant greeting instead.
        h.stt.emitFinal('hi');
        await pump(5);
        final next = h.llm.historySnapshots.last;
        expect(
          next.any((m) => m.content.contains('Greet the user')),
          isFalse,
        );
        expect(
          next.any(
            (m) =>
                m.role == MessageRole.assistant &&
                m.content == 'Hello and welcome! ',
          ),
          isTrue,
        );
      },
    );

    test('Greeting.generated uses a custom instruction when provided', () async {
      final h = _Harness(
        greeting: const Greeting.generated(instruction: 'Say hi in French.'),
      );

      await h.engine.startConversation();
      await pump(5);

      final promptHistory = h.llm.historySnapshots.single;
      expect(promptHistory[1].content, 'Say hi in French.');
    });

    test('no greeting configured leaves startConversation unchanged', () async {
      final h = _Harness();
      final states = <TurnState>[];
      h.engine.turnState.listen(states.add);

      await h.engine.startConversation();
      await pump(10);

      expect(states, [TurnState.listening]);
      expect(h.llm.historySnapshots, isEmpty);
      expect(h.tts.synthesizedText, isEmpty);
    });

    test('startConversation returns without waiting for the greeting to '
        'finish', () async {
      final h = _Harness(greeting: const Greeting.generated());
      final states = <TurnState>[];
      h.engine.turnState.listen(states.add);

      // The generated greeting's LLM stream is deliberately never ended, so if
      // start() awaited the greeting this call would hang. It completing (and
      // the state resting at `thinking`) proves the greeting is fire-and-forget.
      await h.engine.startConversation().timeout(const Duration(seconds: 2));
      await pump(5);

      expect(states, [TurnState.listening, TurnState.thinking]);
    });

    test('stopConversation during the greeting settles at idle', () async {
      final h = _Harness(greeting: const Greeting.generated());
      final states = <TurnState>[];
      h.engine.turnState.listen(states.add);

      await h.engine.startConversation();
      await pump(2);
      h.llm.pushToken('Hello '); // greeting is speaking/thinking
      await pump(2);

      await h.engine.stopConversation();
      await pump(5);

      expect(states.last, TurnState.idle);
    });

    test('interrupt during the greeting returns to listening', () async {
      final h = _Harness(greeting: const Greeting.generated());
      final states = <TurnState>[];
      h.engine.turnState.listen(states.add);

      await h.engine.startConversation();
      await pump(2);
      final cancel = h.llm.lastCancel;

      await h.engine.interrupt();
      await pump(5);

      expect(cancel?.isCancelled, isTrue);
      expect(states.last, TurnState.listening);
    });

    test(
      'full-duplex: a long interim during the greeting barges in and cancels it',
      () async {
        final h = _Harness(
          duplex: DuplexMode.fullDuplex,
          greeting: const Greeting.generated(),
        );
        final speakingReached = Completer<void>();
        h.engine.turnState.listen((s) {
          if (s == TurnState.speaking && !speakingReached.isCompleted) {
            speakingReached.complete();
          }
        });

        await h.engine.startConversation();
        await pump(2);
        h.llm.pushToken('Hello and welcome to the show today! ');
        await speakingReached.future.timeout(const Duration(seconds: 2));

        final cancel = h.llm.lastCancel;
        h.stt.emitInterim('actually wait a moment please');
        await pump(5);

        expect(cancel?.isCancelled, isTrue);
      },
    );

    test('speak() runs a scripted assistant turn through TTS and history',
        () async {
      final h = _Harness();
      await h.engine.startConversation();
      await pump();

      await h.engine.speak('Your order is ready!');
      await pump(30);

      expect(h.tts.synthesizedText, contains('Your order is ready!'));

      h.stt.emitFinal('thanks');
      await pump(5);
      final history = h.llm.historySnapshots.single;
      expect(
        history.any(
          (m) =>
              m.role == MessageRole.assistant &&
              m.content == 'Your order is ready!',
        ),
        isTrue,
      );
    });

    test('speak() while a turn is in flight is dropped', () async {
      final h = _Harness();
      await h.engine.startConversation();
      await pump();

      h.stt.emitFinal('hello');
      await pump(5); // turn is now thinking, LLM stream open

      await h.engine.speak('interjection');
      await pump(5);

      // Only the user turn's synthesis should have happened; speak() dropped.
      expect(h.tts.synthesizedText, isNot(contains('interjection')));
    });
  });

  group('VoiceEngine natural speech and normalization', () {
    Future<void> runOneReply(_Harness h, List<String> tokens) async {
      await h.engine.startConversation();
      await pump();
      h.stt.emitFinal('hi');
      await pump(3);
      for (final t in tokens) {
        h.llm.pushToken(t);
      }
      await h.llm.endStream();
      await pump(30);
    }

    test('TTS input is normalized while transcripts keep the original text',
        () async {
      final h = _Harness();
      final transcripts = <TranscriptEvent>[];
      h.engine.transcripts.listen(transcripts.add);

      await runOneReply(h, ['Say **hi** to ', 'everyone now!']);

      expect(h.tts.synthesizedText, contains('Say hi to everyone now!'));
      // The assistant's original markdown survives on the transcript stream.
      final assistantFinal = transcripts.lastWhere(
        (e) => e.source == TranscriptSource.assistant && e.isFinal,
      );
      expect(assistantFinal.text, 'Say **hi** to everyone now!');
    });

    test(
      'a trailing sentence that normalizes to nothing consumes no AudioQueue '
      'index and the turn still drains',
      () async {
        final h = _Harness();
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);

        // "All done here!" is sentence 0; the trailing emoji has no terminator
        // so it arrives via flush and normalizes to empty.
        await runOneReply(h, ['All done here! ', '🎉🎉🎉']);

        expect(h.sink.enqueuedIndexes, [0]);
        expect(h.tts.synthesizedText, ['All done here!']);
        expect(states.last, TurnState.listening); // drained cleanly
      },
    );

    test(
      'audio tags are stripped for a TTS without tag support and kept for one '
      'with it',
      () async {
        final without = _Harness();
        await runOneReply(without, ['Sure [laughs] ', 'okay then!']);
        expect(without.tts.synthesizedText, contains('Sure okay then!'));

        final with_ = _Harness(ttsSupportsAudioTags: true);
        await runOneReply(with_, ['Sure [laughs] ', 'okay then!']);
        expect(with_.tts.synthesizedText, contains('Sure [laughs] okay then!'));
      },
    );

    test('naturalSpeech augments the seeded system prompt with the voice-style '
        'preamble', () async {
      final h = _Harness(naturalSpeech: true, systemPrompt: 'You are Bo.');
      await h.engine.startConversation();
      await pump();
      h.stt.emitFinal('hi');
      await pump(3);

      final system = h.llm.historySnapshots.single[0];
      expect(system.role, MessageRole.system);
      expect(system.content, startsWith('You are Bo.'));
      expect(
        system.content,
        contains('speaking aloud in a live voice conversation'),
      );
    });

    test('naturalSpeech adds audio-tag guidance only when the TTS supports '
        'tags', () async {
      final tagged = _Harness(naturalSpeech: true, ttsSupportsAudioTags: true);
      await tagged.engine.startConversation();
      await pump();
      tagged.stt.emitFinal('hi');
      await pump(3);
      expect(tagged.llm.historySnapshots.single[0].content, contains('[laughs]'));

      final plain = _Harness(naturalSpeech: true);
      await plain.engine.startConversation();
      await pump();
      plain.stt.emitFinal('hi');
      await pump(3);
      expect(
        plain.llm.historySnapshots.single[0].content,
        isNot(contains('[laughs]')),
      );
    });

    test('naturalSpeech off by default: system prompt is seeded verbatim',
        () async {
      final h = _Harness(systemPrompt: 'You are Bo.');
      await h.engine.startConversation();
      await pump();
      h.stt.emitFinal('hi');
      await pump(3);

      expect(h.llm.historySnapshots.single[0].content, 'You are Bo.');
    });
  });
}
