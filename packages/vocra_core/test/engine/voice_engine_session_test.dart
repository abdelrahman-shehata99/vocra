import 'dart:async';

import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

import 'harness.dart';

/// Runs one full user->assistant turn to completion.
Future<void> runTurn(Harness h, String userText, String reply) async {
  h.stt.emitFinal(userText);
  await pump(5);
  h.llm.pushToken(reply);
  await h.llm.endStream();
  await pump(30);
}

void main() {
  group('VoiceEngine conversation & report', () {
    test(
      'conversation exposes user and assistant messages, never the system prompt',
      () async {
        final h = Harness(systemPrompt: 'SECRET SYSTEM PROMPT');
        await h.engine.startConversation();
        await pump();
        await runTurn(h, 'hello', 'Hi there! ');

        final convo = h.engine.conversation;
        expect(convo.map((m) => m.role), [
          MessageRole.user,
          MessageRole.assistant,
        ]);
        expect(convo.first.content, 'hello');
        expect(
          convo.any((m) => m.content.contains('SECRET SYSTEM PROMPT')),
          isFalse,
        );
      },
    );

    test('conversation is an unmodifiable snapshot', () async {
      final h = Harness();
      await h.engine.startConversation();
      await pump();
      await runTurn(h, 'hi', 'yo ');
      expect(
        () => h.engine.conversation.add(
          const ChatMessage(role: MessageRole.user, content: 'x'),
        ),
        throwsUnsupportedError,
      );
    });

    test('report messages are not truncated by maxHistoryMessages', () async {
      // History caps at 3 (system + 2), but the session record keeps all.
      final h = Harness(maxHistoryMessages: 3);
      await h.engine.startConversation();
      await pump();
      await runTurn(h, 'one', 'r1 ');
      await runTurn(h, 'two', 'r2 ');
      await runTurn(h, 'three', 'r3 ');

      final report = await h.engine.endSession();
      // 3 turns * (user + assistant) = 6 messages, none dropped.
      expect(report.messages, hasLength(6));
      expect(report.messages.first.content, 'one');
    });

    test(
      'endSession stops the conversation and returns a userStopped report',
      () async {
        final h = Harness();
        final states = <TurnState>[];
        h.engine.turnState.listen(states.add);
        await h.engine.startConversation();
        await pump();
        await runTurn(h, 'hi', 'hello ');

        final report = await h.engine.endSession();
        await pump();
        expect(report.endReason, SessionEndReason.userStopped);
        expect(report.turnCount, 1);
        expect(report.turnMetrics, hasLength(1));
        expect(report.messages, hasLength(2));
        expect(states.last, TurnState.idle);
        expect(h.mic.stopCalls, 1);
        expect(h.stt.stopped, isTrue);
      },
    );

    test('sessionEnded also fires on plain stopConversation', () async {
      final h = Harness();
      final reports = <SessionReport>[];
      h.engine.sessionEnded.listen(reports.add);
      await h.engine.startConversation();
      await pump();

      await h.engine.stopConversation();
      await pump();
      expect(reports, hasLength(1));
      expect(reports.single.endReason, SessionEndReason.userStopped);
    });

    test('turnCount matches the number of completed assistant turns', () async {
      final h = Harness();
      await h.engine.startConversation();
      await pump();
      await runTurn(h, 'a', 'A ');
      await runTurn(h, 'b', 'B ');
      final report = await h.engine.endSession();
      expect(report.turnCount, 2);
      expect(report.turnCount, report.turnMetrics.length);
    });

    test('concurrent endSession calls resolve to the same report', () async {
      final h = Harness();
      await h.engine.startConversation();
      await pump();
      await runTurn(h, 'hi', 'yo ');

      final f1 = h.engine.endSession();
      final f2 = h.engine.endSession();
      final r1 = await f1;
      final r2 = await f2;
      expect(identical(r1, r2), isTrue);
    });

    test('endSession after the session ended returns lastReport', () async {
      final h = Harness();
      await h.engine.startConversation();
      await pump();
      final first = await h.engine.endSession();
      final again = await h.engine.endSession();
      expect(identical(first, again), isTrue);
      expect(h.engine.lastReport, same(first));
    });

    test('endSession before startConversation throws StateError', () async {
      final h = Harness();
      expect(() => h.engine.endSession(), throwsStateError);
    });

    test(
      'startConversation clears the previous session record and mute',
      () async {
        final h = Harness();
        await h.engine.startConversation();
        await pump();
        await runTurn(h, 'hi', 'yo ');
        h.engine.mute();
        expect(h.engine.conversation, hasLength(2));

        await h.engine.stopConversation();
        await h.engine.startConversation();
        await pump();
        expect(h.engine.conversation, isEmpty);
        expect(h.engine.isMuted, isFalse);
      },
    );
  });
}
