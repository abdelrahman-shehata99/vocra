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
  group('ElevenLabsTts', () {
    test('returns synthesized bytes and sends the expected request shape',
        () async {
      final adapter = FakeHttpClientAdapter((options) async {
        expect(
          options.path,
          'https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL',
        );
        expect(options.queryParameters['output_format'], 'mp3_22050_32');
        expect(options.headers['xi-api-key'], 'secret-key');
        final body = options.data as Map<String, dynamic>;
        expect(body['text'], 'Hello there.');
        expect(body['model_id'], 'eleven_flash_v2_5');
        expect(
          body['voice_settings'],
          {'stability': 0.5, 'similarity_boost': 0.75},
        );
        return bytesResponseBody([1, 2, 3]);
      });
      final tts = ElevenLabsTts(apiKey: 'secret-key', dio: dioWith(adapter));

      final bytes =
          await tts.synthesize('Hello there.', cancel: Cancellation());

      expect(bytes, [1, 2, 3]);
      expect(tts.audioFormat, 'mp3');
    });

    test('voice, model, and voice settings are configurable', () async {
      final adapter = FakeHttpClientAdapter((options) async {
        expect(options.path, endsWith('/text-to-speech/pNInz6obpgDQGcFmaJgB'));
        final body = options.data as Map<String, dynamic>;
        expect(body['model_id'], 'eleven_multilingual_v2');
        expect(
          body['voice_settings'],
          {'stability': 0.3, 'similarity_boost': 0.9},
        );
        return bytesResponseBody([0]);
      });
      final tts = ElevenLabsTts(
        apiKey: 'key',
        voiceId: 'pNInz6obpgDQGcFmaJgB',
        modelId: 'eleven_multilingual_v2',
        stability: 0.3,
        similarityBoost: 0.9,
        dio: dioWith(adapter),
      );

      await tts.synthesize('hi', cancel: Cancellation());
    });

    test('maps 401 to AuthError', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(401),
      );
      final tts = ElevenLabsTts(apiKey: 'bad', dio: dioWith(adapter));

      await expectLater(
        tts.synthesize('hi', cancel: Cancellation()),
        throwsA(isA<AuthError>()),
      );
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
        return bytesResponseBody([9]);
      });
      final tts = ElevenLabsTts(apiKey: 'key', dio: dioWith(adapter));

      final bytes = await tts.synthesize('hi', cancel: Cancellation());

      expect(calls, 2);
      expect(bytes, [9]);
    });

    test('maps 500 to ProviderError with provider elevenlabs', () async {
      final adapter = FakeHttpClientAdapter(
        (options) async => errorResponseBody(500),
      );
      final tts = ElevenLabsTts(apiKey: 'key', dio: dioWith(adapter));

      await expectLater(
        tts.synthesize('hi', cancel: Cancellation()),
        throwsA(
          isA<ProviderError>()
              .having((e) => e.provider, 'provider', 'elevenlabs'),
        ),
      );
    });
  });
}
