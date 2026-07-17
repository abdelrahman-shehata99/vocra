import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/chat_message.dart';
import '../models/voice_error.dart';
import '../transport/sse_parser.dart';
import '../util/cancellation.dart';
import 'llm_provider.dart';

/// Implements [LlmProvider] against Google's Gemini `streamGenerateContent`
/// endpoint.
///
/// Endpoint, auth header, and response shape verified against the current
/// Gemini API reference (ai.google.dev/api/generate-content) as of writing:
/// `POST {baseUrl}/models/{model}:streamGenerateContent?alt=sse`, key passed
/// via the `x-goog-api-key` header (NOT the `?key=` query parameter, so the
/// secret never appears in URLs or request logs — R6), text chunks in
/// `candidates[0].content.parts[0].text`.
///
/// Gemini's content format differs from the OpenAI-style history the engine
/// keeps, and this adapter owns that mapping:
/// - the `system` message becomes `systemInstruction` (a top-level field,
///   not a content role — Gemini has no `system` role);
/// - `assistant` maps to Gemini's `model` role;
/// - Gemini requires the first content to be a `user` turn, so any leading
///   assistant messages left over from history trimming are dropped
///   (mirrors the HTML reference's `historyForModel`).
class GeminiLlm implements LlmProvider {
  GeminiLlm({
    required this._apiKey,
    this.model = 'gemini-2.5-flash',
    this._baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final String _apiKey;
  final String model;
  final String _baseUrl;
  final Dio _dio;

  static const _sseParser = SseParser();

  @override
  Stream<String> streamCompletion(
    List<ChatMessage> history, {
    required double temperature,
    required int maxTokens,
    required Cancellation cancel,
  }) async* {
    if (cancel.isCancelled) return;

    final cancelToken = CancelToken();
    unawaited(
      cancel.whenCancelled.then((_) {
        if (!cancelToken.isCancelled) cancelToken.cancel('cancelled');
      }),
    );

    final Response<ResponseBody> response;
    try {
      response = await _openStream(
        history,
        temperature: temperature,
        maxTokens: maxTokens,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return; // cancelled before any response
      rethrow;
    }

    // Headers came back, but the connection can still drop mid-stream (R4).
    try {
      await for (final payload in _sseParser.parse(response.data!.stream)) {
        if (cancel.isCancelled) return;
        final text = _extractText(payload);
        if (text != null && text.isNotEmpty) {
          yield text;
        }
      }
    } on VoiceError {
      rethrow; // e.g. the safety-block error thrown by _extractText
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || cancel.isCancelled) return;
      throw _mapError(e, e.response?.statusCode);
    } catch (e) {
      if (cancel.isCancelled) return;
      throw const NetworkError('Connection lost while streaming the response.');
    }
  }

  @override
  Future<void> warmUp() async {
    // Any response still completes the DNS+TCP+TLS handshake and parks the
    // connection in Dio's keep-alive pool. Never throws.
    try {
      await _dio.head<void>('$_baseUrl/models');
    } catch (_) {}
  }

  Future<Response<ResponseBody>> _openStream(
    List<ChatMessage> history, {
    required double temperature,
    required int maxTokens,
    required CancelToken cancelToken,
    bool retriedOn429 = false,
  }) async {
    try {
      return await _dio.post<ResponseBody>(
        '$_baseUrl/models/$model:streamGenerateContent',
        queryParameters: {'alt': 'sse'},
        data: _encodeRequest(
          history,
          temperature: temperature,
          maxTokens: maxTokens,
        ),
        options: Options(
          headers: {
            'x-goog-api-key': _apiKey,
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;

      final statusCode = e.response?.statusCode;
      if (statusCode == 429 && !retriedOn429) {
        await Future<void>.delayed(
          _parseRetryAfter(e.response) ?? const Duration(seconds: 1),
        );
        return _openStream(
          history,
          temperature: temperature,
          maxTokens: maxTokens,
          cancelToken: cancelToken,
          retriedOn429: true,
        );
      }

      throw await _mapErrorAsync(e, statusCode);
    }
  }

  Map<String, dynamic> _encodeRequest(
    List<ChatMessage> history, {
    required double temperature,
    required int maxTokens,
  }) {
    String? systemInstruction;
    final contents = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.role == MessageRole.system) {
        systemInstruction = message.content;
        continue;
      }
      // Gemini requires the conversation to open with a user turn.
      if (contents.isEmpty && message.role == MessageRole.assistant) continue;
      contents.add({
        'role': message.role == MessageRole.assistant ? 'model' : 'user',
        'parts': [
          {'text': message.content},
        ],
      });
    }
    return {
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
      if (systemInstruction != null)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
    };
  }

  /// Like [_mapError], but for the initial-request path where we can still
  /// afford to read the error body: Gemini reports a bad key as HTTP 400
  /// with `API_KEY_INVALID` in the body (not the conventional 401), and
  /// with [ResponseType.stream] that body arrives as a stream that must be
  /// drained before it can be inspected.
  Future<VoiceError> _mapErrorAsync(DioException e, int? statusCode) async {
    if (statusCode == 400) {
      final body = await _readErrorBody(e.response);
      if (body.contains('API_KEY_INVALID') || body.contains('API key')) {
        return const AuthError();
      }
    }
    return _mapError(e, statusCode);
  }

  Future<String> _readErrorBody(Response<dynamic>? response) async {
    final data = response?.data;
    if (data is String) return data;
    if (data is ResponseBody) {
      try {
        final bytes = await data.stream.fold<List<int>>(
          <int>[],
          (acc, chunk) => acc..addAll(chunk),
        );
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return '';
      }
    }
    return data == null ? '' : jsonEncode(data);
  }

  VoiceError _mapError(DioException e, int? statusCode) {
    // Gemini reports auth failures as 403 (or 400, handled in
    // [_mapErrorAsync]), not the conventional 401.
    if (statusCode == 401 || statusCode == 403) {
      return const AuthError();
    }
    if (statusCode == 429) {
      return RateLimitError(retryAfter: _parseRetryAfter(e.response));
    }
    if (statusCode != null) {
      return ProviderError(
        provider: 'gemini',
        statusCode: statusCode,
        message: 'Gemini returned HTTP $statusCode.',
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

  /// Extracts `candidates[0].content.parts[0].text` from one SSE payload.
  /// Malformed events are ignored; a SAFETY finish surfaces as a typed
  /// [ProviderError] so the turn fails loudly instead of going silent.
  String? _extractText(String payload) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(payload) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final candidate = candidates.first as Map<String, dynamic>;
    if (candidate['finishReason'] == 'SAFETY') {
      throw const ProviderError(
        provider: 'gemini',
        statusCode: 200,
        message: 'Gemini blocked the response via safety filters.',
      );
    }
    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return null;
    return (parts.first as Map<String, dynamic>?)?['text'] as String?;
  }
}
