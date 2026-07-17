import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

void main() {
  group('ChatMessage', () {
    test('equality is value-based', () {
      const a = ChatMessage(role: MessageRole.user, content: 'hi');
      const b = ChatMessage(role: MessageRole.user, content: 'hi');
      const c = ChatMessage(role: MessageRole.assistant, content: 'hi');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith overrides only given fields', () {
      const original = ChatMessage(role: MessageRole.system, content: 'p');
      final copy = original.copyWith(content: 'q');

      expect(copy.role, MessageRole.system);
      expect(copy.content, 'q');
    });
  });

  group('TranscriptEvent', () {
    test('equality is value-based', () {
      const a = TranscriptEvent(
        source: TranscriptSource.user,
        text: 'hello',
        isFinal: false,
      );
      const b = TranscriptEvent(
        source: TranscriptSource.user,
        text: 'hello',
        isFinal: false,
      );
      const c = TranscriptEvent(
        source: TranscriptSource.user,
        text: 'hello',
        isFinal: true,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('TurnMetrics', () {
    test('all fields default to null', () {
      const metrics = TurnMetrics();
      expect(metrics.ttft, isNull);
      expect(metrics.firstSentenceReady, isNull);
      expect(metrics.firstTtsReady, isNull);
      expect(metrics.timeToFirstVoice, isNull);
      expect(metrics.total, isNull);
    });

    test('copyWith merges fields', () {
      const metrics = TurnMetrics(ttft: Duration(milliseconds: 100));
      final updated = metrics.copyWith(total: const Duration(seconds: 1));

      expect(updated.ttft, const Duration(milliseconds: 100));
      expect(updated.total, const Duration(seconds: 1));
    });

    test('equality is value-based', () {
      const a = TurnMetrics(ttft: Duration(milliseconds: 50));
      const b = TurnMetrics(ttft: Duration(milliseconds: 50));
      expect(a, equals(b));
    });
  });

  group('VoiceError', () {
    test('subtypes carry their message', () {
      const auth = AuthError();
      const rate = RateLimitError(retryAfter: Duration(seconds: 5));
      const network = NetworkError();
      const provider = ProviderError(
        provider: 'groq',
        statusCode: 500,
        message: 'boom',
      );
      const config = ConfigError('bad config');

      expect(auth.message, contains('Authentication'));
      expect(rate.retryAfter, const Duration(seconds: 5));
      expect(network.message, isNotEmpty);
      expect(provider.provider, 'groq');
      expect(provider.statusCode, 500);
      expect(config.message, 'bad config');
    });
  });
}
