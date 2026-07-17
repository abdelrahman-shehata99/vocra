import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/voice_error.dart';
import '../util/cancellation.dart';
import 'tts_provider.dart';

/// Implements [TtsProvider] against ElevenLabs' text-to-speech REST
/// endpoint.
///
/// Endpoint and auth verified against the current ElevenLabs API reference
/// (elevenlabs.io/docs/api-reference/text-to-speech/convert) as of writing:
/// `POST {baseUrl}/text-to-speech/{voiceId}`, key via the `xi-api-key`
/// header, `output_format` as a query parameter.
///
/// Defaults mirror the HTML reference implementation: voice "Sarah"
/// (`EXAVITQu4vr4xnSDxMaL`), model `eleven_flash_v2_5` (ElevenLabs' lowest-
/// latency model — the right trade-off for conversational voice, same
/// reasoning as [DeepgramTts]' Aura-1 default), `mp3_22050_32` output
/// (small clips decode fast on-device), stability 0.5 / similarity 0.75.
///
/// Bracketed audio tags like `[laughs]`, `[sighs]`, or `[whispers]` are only
/// rendered by the `eleven_v3` model family (see [supportsAudioTags]); the
/// flash/turbo models read them aloud, so the engine strips them for those.
/// `eleven_v3` is more expressive but higher-latency than the flash default.
class ElevenLabsTts implements TtsProvider {
  ElevenLabsTts({
    required this._apiKey,
    this.voiceId = 'EXAVITQu4vr4xnSDxMaL',
    this.modelId = 'eleven_flash_v2_5',
    this.stability = 0.5,
    this.similarityBoost = 0.75,
    this.style,
    this.useSpeakerBoost,
    this._baseUrl = 'https://api.elevenlabs.io/v1',
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final String _apiKey;
  final String voiceId;
  final String modelId;
  final double stability;
  final double similarityBoost;

  /// Optional style exaggeration (0.0–1.0). Higher values are more expressive
  /// but can raise latency and reduce stability on some models. Sent only when
  /// set, so the default request shape is unchanged.
  final double? style;

  /// Optional speaker-boost toggle for clarity/similarity. Sent only when set.
  final bool? useSpeakerBoost;

  final String _baseUrl;
  final Dio _dio;

  @override
  String get audioFormat => 'mp3';

  /// Only the `eleven_v3` model family renders bracketed audio tags like
  /// `[laughs]` as delivery cues; other models would speak them, so the engine
  /// strips tags unless this is true.
  @override
  bool get supportsAudioTags => modelId.startsWith('eleven_v3');

  @override
  Future<void> warmUp() async {
    // Any response still completes the DNS+TCP+TLS handshake and parks the
    // connection in Dio's keep-alive pool. Never throws.
    try {
      await _dio.head<void>('$_baseUrl/text-to-speech/$voiceId');
    } catch (_) {}
  }

  @override
  Future<Uint8List> synthesize(
    String text, {
    required Cancellation cancel,
  }) async {
    final cancelToken = CancelToken();
    cancel.whenCancelled.then((_) {
      if (!cancelToken.isCancelled) cancelToken.cancel('cancelled');
    });
    return _synthesize(text, cancelToken: cancelToken, retriedOn429: false);
  }

  Future<Uint8List> _synthesize(
    String text, {
    required CancelToken cancelToken,
    required bool retriedOn429,
  }) async {
    try {
      final response = await _dio.post<List<int>>(
        '$_baseUrl/text-to-speech/$voiceId',
        queryParameters: {'output_format': 'mp3_22050_32'},
        data: {
          'text': text,
          'model_id': modelId,
          'voice_settings': {
            'stability': stability,
            'similarity_boost': similarityBoost,
            if (style != null) 'style': style,
            if (useSpeakerBoost != null) 'use_speaker_boost': useSpeakerBoost,
          },
        },
        options: Options(
          headers: {
            'xi-api-key': _apiKey,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          responseType: ResponseType.bytes,
        ),
        cancelToken: cancelToken,
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;

      // Retry once on 429, mirroring GroqLlm/DeepgramTts and the HTML
      // reference's synthesizeWithRetry.
      if (e.response?.statusCode == 429 && !retriedOn429) {
        await Future<void>.delayed(
          _parseRetryAfter(e.response) ?? const Duration(seconds: 1),
        );
        if (cancelToken.isCancelled) rethrow;
        return _synthesize(text, cancelToken: cancelToken, retriedOn429: true);
      }

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
        provider: 'elevenlabs',
        statusCode: statusCode,
        message: 'ElevenLabs TTS returned HTTP $statusCode.',
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
