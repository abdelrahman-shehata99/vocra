import 'dart:async';

import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

import 'harness.dart';

Future<void> runTurn(Harness h, String userText, String reply) async {
  h.stt.emitFinal(userText);
  await pump(5);
  h.llm.pushToken(reply);
  await h.llm.endStream();
  await pump(30);
}

/// Waits for [check] to hold, pumping the event loop, up to [tries] times.
Future<void> waitFor(bool Function() check, {int tries = 50}) async {
  for (var i = 0; i < tries && !check(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('SessionPolicies — max duration', () {
    test('ends the session with reason maxDurationReached', () async {
      final h = Harness(
        policies: const SessionPolicies(
          maxDuration: Duration(milliseconds: 30),
        ),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();

      await waitFor(() => report != null);
      expect(report, isNotNull);
      expect(report!.endReason, SessionEndReason.maxDurationReached);
    });

    test('speaks the endMessage before tearing down', () async {
      final h = Harness(
        policies: const SessionPolicies(
          maxDuration: Duration(milliseconds: 30),
          endMessage: 'Goodbye now.',
        ),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();

      await waitFor(() => report != null, tries: 200);
      expect(report, isNotNull);
      // The farewell was spoken → it's the last assistant message.
      expect(report!.messages.last.role, MessageRole.assistant);
      expect(report!.messages.last.content, 'Goodbye now.');
      expect(h.tts.synthesizedText, contains('Goodbye now.'));
    });

    test('with no endMessage tears down immediately', () async {
      final h = Harness(
        policies: const SessionPolicies(
          maxDuration: Duration(milliseconds: 30),
        ),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();

      await waitFor(() => report != null);
      expect(report!.messages, isEmpty);
      expect(h.tts.synthesizedText, isEmpty);
    });

    test('timer never fires after stopConversation', () async {
      final h = Harness(
        policies: const SessionPolicies(
          maxDuration: Duration(milliseconds: 40),
        ),
      );
      final reasons = <SessionEndReason>[];
      h.engine.sessionEnded.listen((r) => reasons.add(r.endReason));
      await h.engine.startConversation();
      await h.engine.stopConversation();

      // Wait past the max-duration deadline.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Exactly one end (the userStopped one), no maxDurationReached.
      expect(reasons, [SessionEndReason.userStopped]);
    });
  });

  group('SessionPolicies — silence timeout', () {
    test('ends a quiet listening session', () async {
      final h = Harness(
        policies: const SessionPolicies(
          silenceTimeout: Duration(milliseconds: 30),
        ),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();

      await waitFor(() => report != null);
      expect(report!.endReason, SessionEndReason.silenceTimeout);
    });

    test('an interim transcript resets the silence timer', () async {
      final h = Harness(
        policies: const SessionPolicies(
          silenceTimeout: Duration(milliseconds: 60),
        ),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();

      // Keep speaking (interims) faster than the timeout for a while.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        h.stt.emitInterim('still here $i');
      }
      expect(report, isNull, reason: 'resets kept the session alive');

      // Now go quiet — it should fire.
      await waitFor(() => report != null, tries: 100);
      expect(report!.endReason, SessionEndReason.silenceTimeout);
    });

    test('is not armed while a turn is in flight', () async {
      final h = Harness(
        policies: const SessionPolicies(
          silenceTimeout: Duration(milliseconds: 40),
        ),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();

      // Start a turn and stall it (no endStream) past the timeout.
      h.stt.emitFinal('hello');
      await pump(5);
      h.llm.pushToken('thinking... ');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Still mid-turn — silence timeout must not have ended the session.
      expect(report, isNull);

      await h.llm.endStream();
      await pump(30);
    });
  });

  group('SessionPolicies — end phrases', () {
    test('a final end phrase ends the session without an LLM call', () async {
      final h = Harness(
        policies: const SessionPolicies(endPhrases: ['goodbye']),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();
      await pump();

      h.stt.emitFinal('okay, goodbye!');
      await waitFor(() => report != null);
      expect(report!.endReason, SessionEndReason.endPhrase);
      // No LLM turn ran for the goodbye.
      expect(h.llm.historySnapshots, isEmpty);
      // But the goodbye is recorded as the user's last message.
      expect(report!.messages.last.role, MessageRole.user);
      expect(report!.messages.last.content, 'okay, goodbye!');
    });

    test('matching is case- and punctuation-insensitive', () async {
      final h = Harness(
        policies: const SessionPolicies(endPhrases: ['talk to you soon']),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();
      await pump();

      h.stt.emitFinal('Alright, TALK to you soon.');
      await waitFor(() => report != null);
      expect(report!.endReason, SessionEndReason.endPhrase);
    });

    test('matches ends-with but not a mid-sentence mention', () async {
      final h = Harness(
        policies: const SessionPolicies(endPhrases: ['goodbye']),
      );
      SessionReport? report;
      h.engine.sessionEnded.listen((r) => report = r);
      await h.engine.startConversation();
      await pump();

      // Mid-sentence mention must NOT end the session.
      h.stt.emitFinal("don't say goodbye yet");
      await pump(10);
      expect(report, isNull);
      // The LLM turn runs normally for it.
      await waitFor(() => h.llm.historySnapshots.isNotEmpty);
      expect(h.llm.historySnapshots, isNotEmpty);
    });
  });

  group('SessionPolicies — assistantName', () {
    test('appears in the seeded system prompt', () async {
      final h = Harness(assistantName: 'Riley', systemPrompt: 'Be helpful.');
      await h.engine.startConversation();
      await pump();
      h.stt.emitFinal('hi');
      await pump(5);

      final systemMessage = h.llm.historySnapshots.first.first;
      expect(systemMessage.role, MessageRole.system);
      expect(systemMessage.content, contains('Riley'));
      expect(systemMessage.content, contains('Be helpful.'));

      h.llm.pushToken('Hi! ');
      await h.llm.endStream();
      await pump(30);
    });
  });
}
