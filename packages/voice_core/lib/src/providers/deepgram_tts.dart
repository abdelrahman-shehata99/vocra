import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/voice_error.dart';
import '../util/cancellation.dart';
import 'tts_provider.dart';

/// Implements [TtsProvider] against Deepgram's text-to-speech REST endpoint
/// (spec §7.3).
///
/// Endpoint and auth header verified against Deepgram's current docs as of
/// writing: `POST {baseUrl}/speak`, `Authorization: Token <key>` — note
/// this is `Token`, not `Bearer` (R-of-the-Do-Not list, spec §13). The
/// default voice model uses the current Aura-2 naming convention
/// (`aura-2-<voice>-en`), which supersedes the original Aura-1
/// `aura-asteria-en` style name used in earlier examples.
class DeepgramTts implements TtsProvider {
  DeepgramTts({
    required String apiKey,
    this.model = 'aura-2-thalia-en',
    String baseUrl = 'https://api.deepgram.com/v1',
    Dio? dio,
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl,
       _dio = dio ?? Dio();

  final String _apiKey;
  final String model;
  final String _baseUrl;
  final Dio _dio;

  @override
  String get audioFormat => 'mp3';

  @override
  Future<Uint8List> synthesize(
    String text, {
    required Cancellation cancel,
  }) async {
    final cancelToken = CancelToken();
    cancel.whenCancelled.then((_) {
      if (!cancelToken.isCancelled) cancelToken.cancel('cancelled');
    });

    try {
      final response = await _dio.post<List<int>>(
        '$_baseUrl/speak',
        queryParameters: {'model': model, 'encoding': audioFormat},
        data: {'text': text},
        options: Options(
          headers: {
            'Authorization': 'Token $_apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.bytes,
        ),
        cancelToken: cancelToken,
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw _mapError(e);
    }
  }

  VoiceError _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) {
      return const AuthError();
    }
    if (statusCode == 429) {
      return RateLimitError(retryAfter: _parseRetryAfter(e.response));
    }
    if (statusCode != null) {
      return ProviderError(
        provider: 'deepgram',
        statusCode: statusCode,
        message: 'Deepgram TTS returned HTTP $statusCode.',
      );
    }
    return const NetworkError();
  }

  Duration? _parseRetryAfter(Response<dynamic>? response) {
    final header = response?.headers.value('retry-after');
    if (header == null) return null;
    final seconds = int.tryParse(header);
    return seconds == null ? null : Duration(seconds: seconds);
  }
}
