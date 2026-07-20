import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

import 'fakes.dart';

Dio dioWith(FakeHttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('OpenAiLlm', () {
    test('streams tokens parsed from delta.content', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        return sseResponseBody([
          'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n',
          'data: {"choices":[{"delta":{"content":" there"}}]}\n\n',
          'data: [DONE]\n\n',
        ]);
      });
      final llm = OpenAiLlm(apiKey: 'key', dio: dioWith(adapter));

      final tokens = await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.7,
            maxTokens: 100,
            cancel: Cancellation(),
          )
          .toList();

      expect(tokens, ['Hi', ' there']);
    });

    test('posts to the OpenAI endpoint with Bearer auth, default model, '
        'max_completion_tokens, and no reasoning fields', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        expect(options.path, 'https://api.openai.com/v1/chat/completions');
        expect(options.headers['Authorization'], 'Bearer secret-key');
        final body = options.data as Map<String, dynamic>;
        expect(body['model'], 'gpt-4.1-mini');
        expect(body['stream'], isTrue);
        expect(body['max_completion_tokens'], 64);
        expect(body.containsKey('reasoning_effort'), isFalse);
        expect(body.containsKey('include_reasoning'), isFalse);
        return sseResponseBody(['data: [DONE]\n\n']);
      });
      final llm = OpenAiLlm(apiKey: 'secret-key', dio: dioWith(adapter));

      await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.5,
            maxTokens: 64,
            cancel: Cancellation(),
          )
          .toList();
    });

    test('maps 401 to AuthError with provider "openai"', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
        );
      });
      final llm = OpenAiLlm(apiKey: 'bad', dio: dioWith(adapter));

      expect(
        () => llm
            .streamCompletion(
              const [ChatMessage(role: MessageRole.user, content: 'hi')],
              temperature: 0.7,
              maxTokens: 100,
              cancel: Cancellation(),
            )
            .toList(),
        throwsA(isA<AuthError>()),
      );
    });

    test('maps a 500 to ProviderError carrying provider "openai"', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 500),
        );
      });
      final llm = OpenAiLlm(apiKey: 'key', dio: dioWith(adapter));

      try {
        await llm
            .streamCompletion(
              const [ChatMessage(role: MessageRole.user, content: 'hi')],
              temperature: 0.7,
              maxTokens: 100,
              cancel: Cancellation(),
            )
            .toList();
        fail('expected a ProviderError');
      } on ProviderError catch (e) {
        expect(e.provider, 'openai');
        expect(e.statusCode, 500);
      }
    });
  });
}
