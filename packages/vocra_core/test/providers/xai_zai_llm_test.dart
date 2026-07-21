import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

import 'fakes.dart';

Dio dioWith(FakeHttpClientAdapter adapter) =>
    Dio()..httpClientAdapter = adapter;

Future<List<String>> stream(LlmProvider llm) => llm
    .streamCompletion(
      const [ChatMessage(role: MessageRole.user, content: 'hi')],
      temperature: 0.5,
      maxTokens: 64,
      cancel: Cancellation(),
    )
    .toList();

void main() {
  group('XaiLlm', () {
    test(
      'posts to the xAI endpoint with Bearer auth and default model',
      () async {
        final adapter = FakeHttpClientAdapter((options) async {
          expect(options.path, 'https://api.x.ai/v1/chat/completions');
          expect(options.headers['Authorization'], 'Bearer secret');
          final body = options.data as Map<String, dynamic>;
          expect(body['model'], 'grok-4.3');
          expect(body['max_completion_tokens'], 64);
          return sseResponseBody(['data: [DONE]\n\n']);
        });
        await stream(XaiLlm(apiKey: 'secret', dio: dioWith(adapter)));
      },
    );

    test('maps 500 to ProviderError carrying provider "xai"', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 500),
        );
      });
      try {
        await stream(XaiLlm(apiKey: 'k', dio: dioWith(adapter)));
        fail('expected a ProviderError');
      } on ProviderError catch (e) {
        expect(e.provider, 'xai');
      }
    });
  });

  group('ZaiLlm', () {
    test(
      'posts to the Z.ai endpoint using max_tokens (not max_completion_tokens)',
      () async {
        final adapter = FakeHttpClientAdapter((options) async {
          expect(options.path, 'https://api.z.ai/api/paas/v4/chat/completions');
          expect(options.headers['Authorization'], 'Bearer secret');
          final body = options.data as Map<String, dynamic>;
          expect(body['model'], 'glm-4.6');
          // Z.ai only accepts the legacy field name.
          expect(body['max_tokens'], 64);
          expect(body.containsKey('max_completion_tokens'), isFalse);
          return sseResponseBody(['data: [DONE]\n\n']);
        });
        await stream(ZaiLlm(apiKey: 'secret', dio: dioWith(adapter)));
      },
    );

    test('maps 401 to AuthError', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
        );
      });
      expect(
        () => stream(ZaiLlm(apiKey: 'bad', dio: dioWith(adapter))),
        throwsA(isA<AuthError>()),
      );
    });
  });
}
