import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

import 'fakes.dart';

Dio dioWith(FakeHttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('GroqLlm', () {
    test('streams tokens parsed from delta.content fixture', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        return sseResponseBody([
          'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n',
          'data: {"choices":[{"delta":{"content":" world"}}]}\n\n',
          'data: {"choices":[{"delta":{}}]}\n\n',
          'data: [DONE]\n\n',
        ]);
      });
      final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));

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

    test('sends the expected request shape', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        expect(options.path, 'https://api.groq.com/openai/v1/chat/completions');
        expect(options.headers['Authorization'], 'Bearer secret-key');
        final body = options.data as Map<String, dynamic>;
        expect(body['model'], 'llama-3.1-8b-instant');
        expect(body['stream'], isTrue);
        expect(body['max_completion_tokens'], 50);
        expect(body['temperature'], 0.5);
        return sseResponseBody(['data: [DONE]\n\n']);
      });
      final llm = GroqLlm(apiKey: 'secret-key', dio: dioWith(adapter));

      await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.5,
            maxTokens: 50,
            cancel: Cancellation(),
          )
          .toList();
    });

    test('maps 401 to AuthError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(401),
      );
      final llm = GroqLlm(apiKey: 'bad', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(stream, emitsError(isA<AuthError>()));
    });

    test('maps 5xx to ProviderError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(503),
      );
      final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(
        stream,
        emitsError(
          isA<ProviderError>()
              .having((e) => e.provider, 'provider', 'groq')
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('retries once on 429 then succeeds', () async {
      var attempt = 0;
      final adapter = FakeHttpClientAdapter((options) async {
        attempt++;
        if (attempt == 1) {
          return errorResponseBody(
            429,
            headers: {
              'retry-after': ['0'],
            },
          );
        }
        return sseResponseBody([
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
          'data: [DONE]\n\n',
        ]);
      });
      final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));

      final tokens = await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.7,
            maxTokens: 100,
            cancel: Cancellation(),
          )
          .toList();

      expect(attempt, 2);
      expect(tokens, ['ok']);
    });

    test('maps a second consecutive 429 to RateLimitError', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        return errorResponseBody(
          429,
          headers: {
            'retry-after': ['0'],
          },
        );
      });
      final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));

      final stream = llm.streamCompletion(
        const [ChatMessage(role: MessageRole.user, content: 'hi')],
        temperature: 0.7,
        maxTokens: 100,
        cancel: Cancellation(),
      );

      await expectLater(stream, emitsError(isA<RateLimitError>()));
    });

    test('ignores a malformed SSE payload instead of throwing', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        return sseResponseBody([
          'data: not json\n\n',
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
          'data: [DONE]\n\n',
        ]);
      });
      final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));

      final tokens = await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.7,
            maxTokens: 100,
            cancel: Cancellation(),
          )
          .toList();

      expect(tokens, ['ok']);
    });

    test('stops emitting tokens promptly once cancelled', () async {
      final controller = StreamController<Uint8List>();
      final adapter = FakeHttpClientAdapter((options) async {
        return ResponseBody(controller.stream, 200);
      });
      final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));
      final cancel = Cancellation();

      final received = <String>[];
      final sub = llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0.7,
            maxTokens: 100,
            cancel: cancel,
          )
          .listen(received.add);

      void send(String s) => controller.add(Uint8List.fromList(s.codeUnits));

      send('data: {"choices":[{"delta":{"content":"first"}}]}\n\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, ['first']);

      cancel.cancel();
      send('data: {"choices":[{"delta":{"content":"second"}}]}\n\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, ['first']); // "second" must never arrive

      await sub.cancel();
      await controller.close();
    });

    test(
      'maps a connection drop mid-stream to NetworkError instead of leaking a raw exception',
      () async {
        final controller = StreamController<Uint8List>();
        final adapter = FakeHttpClientAdapter((options) async {
          return ResponseBody(controller.stream, 200);
        });
        final llm = GroqLlm(apiKey: 'key', dio: dioWith(adapter));

        final stream = llm.streamCompletion(
          const [ChatMessage(role: MessageRole.user, content: 'hi')],
          temperature: 0.7,
          maxTokens: 100,
          cancel: Cancellation(),
        );

        final received = <String>[];
        final errors = <Object>[];
        final done = Completer<void>();
        stream.listen(received.add, onError: errors.add, onDone: done.complete);

        controller.add(
          Uint8List.fromList(
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n'.codeUnits,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        controller.addError(const SocketException('Connection reset by peer'));
        await done.future.timeout(const Duration(seconds: 2));

        expect(received, ['partial']);
        expect(errors, [isA<NetworkError>()]);
      },
    );
  });
}
