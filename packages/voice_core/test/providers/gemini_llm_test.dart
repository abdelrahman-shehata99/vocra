import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

import 'fakes.dart';

Dio dioWith(FakeHttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

String _chunk(String text) =>
    'data: {"candidates":[{"content":{"parts":[{"text":"$text"}],'
    '"role":"model"}}]}\n\n';

void main() {
  group('GeminiLlm', () {
    test('streams text parsed from candidates.content.parts fixture',
        () async {
      final adapter = FakeHttpClientAdapter((options) async {
        return sseResponseBody([_chunk('Hello'), _chunk(' world')]);
      });
      final llm = GeminiLlm(apiKey: 'key', dio: dioWith(adapter));

      final tokens = await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.7,
            maxTokens: 100,
            cancel: Cancellation(),
          )
          .toList();

      expect(tokens, ['Hello', ' world']);
    });

    test(
      'maps history to Gemini format: system -> systemInstruction, '
      'assistant -> model role, leading assistant dropped',
      () async {
        final adapter = FakeHttpClientAdapter((options) async {
          expect(
            options.path,
            'https://generativelanguage.googleapis.com/v1beta/models/'
            'gemini-2.5-flash:streamGenerateContent',
          );
          expect(options.queryParameters['alt'], 'sse');
          // Key travels in a header, never in the URL (R6).
          expect(options.headers['x-goog-api-key'], 'secret-key');
          expect(options.uri.toString(), isNot(contains('secret-key')));

          final body = options.data as Map<String, dynamic>;
          expect(
            body['systemInstruction'],
            {
              'parts': [
                {'text': 'be nice'},
              ],
            },
          );
          final contents = body['contents'] as List<dynamic>;
          // The leading assistant message (left over from trimming) is
          // dropped: Gemini requires the first content to be a user turn.
          expect(contents, hasLength(2));
          expect((contents[0] as Map<String, dynamic>)['role'], 'user');
          expect((contents[1] as Map<String, dynamic>)['role'], 'model');
          final config = body['generationConfig'] as Map<String, dynamic>;
          expect(config['temperature'], 0.5);
          expect(config['maxOutputTokens'], 50);
          return sseResponseBody([_chunk('ok')]);
        });
        final llm = GeminiLlm(apiKey: 'secret-key', dio: dioWith(adapter));

        await llm
            .streamCompletion(
              const [
                ChatMessage(role: MessageRole.system, content: 'be nice'),
                ChatMessage(role: MessageRole.assistant, content: 'orphaned'),
                ChatMessage(role: MessageRole.user, content: 'hi'),
                ChatMessage(role: MessageRole.assistant, content: 'hello'),
              ],
              temperature: 0.5,
              maxTokens: 50,
              cancel: Cancellation(),
            )
            .toList();
      },
    );

    test('maps 403 to AuthError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(403),
      );
      final llm = GeminiLlm(apiKey: 'bad', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(stream, emitsError(isA<AuthError>()));
    });

    test('maps 400 API_KEY_INVALID to AuthError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(
          400,
          body: '{"error":{"status":"INVALID_ARGUMENT",'
              '"message":"API key not valid","details":'
              '[{"reason":"API_KEY_INVALID"}]}}',
        ),
      );
      final llm = GeminiLlm(apiKey: 'bad', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(stream, emitsError(isA<AuthError>()));
    });

    test('retries once on 429 then succeeds', () async {
      var calls = 0;
      final adapter = FakeHttpClientAdapter((options) async {
        calls++;
        if (calls == 1) {
          return errorResponseBody(
            429,
            headers: {
              'retry-after': ['0'],
            },
          );
        }
        return sseResponseBody([_chunk('recovered')]);
      });
      final llm = GeminiLlm(apiKey: 'key', dio: dioWith(adapter));

      final tokens = await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.7,
            maxTokens: 100,
            cancel: Cancellation(),
          )
          .toList();

      expect(calls, 2);
      expect(tokens, ['recovered']);
    });

    test('maps 500 to ProviderError with provider gemini', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(500),
      );
      final llm = GeminiLlm(apiKey: 'key', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(
        stream,
        emitsError(
          isA<ProviderError>().having((e) => e.provider, 'provider', 'gemini'),
        ),
      );
    });

    test('a SAFETY finish surfaces as a typed ProviderError', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        return sseResponseBody([
          _chunk('so far so good'),
          'data: {"candidates":[{"finishReason":"SAFETY"}]}\n\n',
        ]);
      });
      final llm = GeminiLlm(apiKey: 'key', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(
        stream,
        emitsInOrder([
          'so far so good',
          emitsError(isA<ProviderError>()),
        ]),
      );
    });
  });
}
