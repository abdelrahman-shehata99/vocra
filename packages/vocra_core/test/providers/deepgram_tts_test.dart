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
  group('DeepgramTts', () {
    test('audioFormat is mp3', () {
      final tts = DeepgramTts(apiKey: 'key');
      expect(tts.audioFormat, 'mp3');
    });

    test('supportsAudioTags is false: Aura has no tag support', () {
      expect(DeepgramTts(apiKey: 'key').supportsAudioTags, isFalse);
    });

    test('returns bytes from a successful response', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => bytesResponseBody([1, 2, 3, 4]),
      );
      final tts = DeepgramTts(apiKey: 'key', dio: dioWith(adapter));

      final bytes = await tts.synthesize('hello', cancel: Cancellation());

      expect(bytes, [1, 2, 3, 4]);
    });

    test('sends the expected request shape with Token auth', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        expect(options.path, 'https://api.deepgram.com/v1/speak');
        expect(options.headers['Authorization'], 'Token secret-key');
        expect(options.queryParameters['model'], 'aura-asteria-en');
        expect(options.queryParameters['encoding'], 'mp3');
        final body = options.data as Map<String, dynamic>;
        expect(body['text'], 'hello there');
        return bytesResponseBody([0]);
      });
      final tts = DeepgramTts(apiKey: 'secret-key', dio: dioWith(adapter));

      await tts.synthesize('hello there', cancel: Cancellation());
    });

    test('maps 401 to AuthError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(401),
      );
      final tts = DeepgramTts(apiKey: 'bad', dio: dioWith(adapter));

      await expectLater(
        tts.synthesize('hi', cancel: Cancellation()),
        throwsA(isA<AuthError>()),
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
        return bytesResponseBody([1, 2, 3]);
      });
      final tts = DeepgramTts(apiKey: 'key', dio: dioWith(adapter));

      final bytes = await tts.synthesize('hi', cancel: Cancellation());
      expect(attempt, 2);
      expect(bytes, [1, 2, 3]);
    });

    test('maps a second consecutive 429 to RateLimitError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(
          429,
          headers: {
            'retry-after': ['0'],
          },
        ),
      );
      final tts = DeepgramTts(apiKey: 'key', dio: dioWith(adapter));

      await expectLater(
        tts.synthesize('hi', cancel: Cancellation()),
        throwsA(isA<RateLimitError>()),
      );
    });

    test('maps 5xx to ProviderError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(500),
      );
      final tts = DeepgramTts(apiKey: 'key', dio: dioWith(adapter));

      await expectLater(
        tts.synthesize('hi', cancel: Cancellation()),
        throwsA(
          isA<ProviderError>()
              .having((e) => e.provider, 'provider', 'deepgram')
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('maps a malformed (network) failure to NetworkError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'no internet',
        ),
      );
      final tts = DeepgramTts(apiKey: 'key', dio: dioWith(adapter));

      await expectLater(
        tts.synthesize('hi', cancel: Cancellation()),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
