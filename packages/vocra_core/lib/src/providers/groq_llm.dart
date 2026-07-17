import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/chat_message.dart';
import '../models/voice_error.dart';
import '../transport/sse_parser.dart';
import '../util/cancellation.dart';
import 'llm_provider.dart';

/// Implements [LlmProvider] against Groq's OpenAI-compatible chat
/// completions endpoint (spec §7.1).
///
/// Endpoint, auth header, and field names verified against Groq's current
/// API reference (console.groq.com/docs/api-reference) as of writing:
/// `POST {baseUrl}/chat/completions`, `Authorization: Bearer <key>`, and
/// `max_completion_tokens` (not the older `max_tokens` alias) for the token
/// limit.
///
/// The default [model] is Groq's `openai/gpt-oss-20b`. The previous default
/// `llama-3.1-8b-instant` was deprecated by Groq on 2026-06-17 and is
/// **retired on 2026-08-16**, so it is no longer a safe default. `gpt-oss-20b`
/// is a reasoning model; for voice latency this adapter automatically sends
/// `reasoning_effort: 'low'` and `include_reasoning: false` for any
/// `openai/gpt-oss*` model (see [_isGptOss]) so it doesn't "think" out loud
/// before the first spoken word. Consumers can pin any model per-app via
/// `GroqLlm(model: ...)`. See console.groq.com/docs/reasoning.
class GroqLlm implements LlmProvider {
  GroqLlm({
    required String apiKey,
    this.model = 'openai/gpt-oss-20b',
    String baseUrl = 'https://api.groq.com/openai/v1',
    Dio? dio,
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl,
       _dio = dio ?? Dio();

  final String _apiKey;
  final String model;
  final String _baseUrl;
  final Dio _dio;

  static const _sseParser = SseParser();

  /// Groq's `openai/gpt-oss*` models are reasoning models that accept the
  /// `reasoning_effort` / `include_reasoning` parameters; other Groq models
  /// (e.g. the Llama family) reject them.
  bool get _isGptOss => model.startsWith('openai/gpt-oss');

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

    // The initial request succeeded and headers came back, but the
    // connection can still drop mid-stream (R4: every failure — not just
    // the initial request — must surface as a typed VoiceError).
    try {
      await for (final payload in _sseParser.parse(response.data!.stream)) {
        if (cancel.isCancelled) return;
        final content = _extractDeltaContent(payload);
        if (content != null && content.isNotEmpty) {
          yield content;
        }
      }
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
    // Any response (even 401/404) still completes the DNS+TCP+TLS handshake
    // and parks the connection in Dio's keep-alive pool. Never throws.
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
        '$_baseUrl/chat/completions',
        data: {
          'model': model,
          'messages': history.map(_encodeMessage).toList(),
          'stream': true,
          'temperature': temperature,
          'max_completion_tokens': maxTokens,
          // Reasoning models: keep the pre-token "thinking" minimal and out of
          // the stream so the first spoken word arrives fast (see [_isGptOss]).
          if (_isGptOss) 'reasoning_effort': 'low',
          if (_isGptOss) 'include_reasoning': false,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
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

      throw _mapError(e, statusCode);
    }
  }

  VoiceError _mapError(DioException e, int? statusCode) {
    if (statusCode == 401) {
      return const AuthError();
    }
    if (statusCode == 429) {
      return RateLimitError(retryAfter: _parseRetryAfter(e.response));
    }
    if (statusCode != null) {
      return ProviderError(
        provider: 'groq',
        statusCode: statusCode,
        message: 'Groq returned HTTP $statusCode.',
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

  Map<String, String> _encodeMessage(ChatMessage message) => {
    'role': _roleName(message.role),
    'content': message.content,
  };

  String _roleName(MessageRole role) => switch (role) {
    MessageRole.system => 'system',
    MessageRole.user => 'user',
    MessageRole.assistant => 'assistant',
  };

  /// Extracts `choices[0].delta.content` from one SSE payload, per spec
  /// §7.1. Malformed events are ignored rather than crashing the stream.
  String? _extractDeltaContent(String payload) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(payload) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final delta = (choices.first as Map<String, dynamic>?)?['delta'];
    return (delta as Map<String, dynamic>?)?['content'] as String?;
  }
}
