/// Base type for every typed failure the SDK surfaces (spec §4, R4).
///
/// Adapters must never throw raw strings or unwrapped platform exceptions —
/// everything that can fail maps to one of the subtypes below.
sealed class VoiceError implements Exception {
  const VoiceError(this.message);

  /// Human-readable description. Must never contain API keys or full
  /// transcripts (R6) — callers may log this at error level.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The provider rejected the request because of a bad or missing API key.
class AuthError extends VoiceError {
  const AuthError([
    String message = 'Authentication failed: invalid or missing API key.',
  ]) : super(message);
}

/// The provider responded with HTTP 429.
class RateLimitError extends VoiceError {
  const RateLimitError({
    this.retryAfter,
    String message = 'Rate limit exceeded.',
  }) : super(message);

  /// Value of the provider's `Retry-After` header, if present.
  final Duration? retryAfter;
}

/// A transport-level failure: no connection, DNS failure, timeout, dropped
/// socket, etc. — distinct from a [ProviderError], which means the provider
/// was reached but returned an error.
class NetworkError extends VoiceError {
  const NetworkError([String message = 'Network error.']) : super(message);
}

/// The provider was reached but returned an error response.
class ProviderError extends VoiceError {
  const ProviderError({
    required this.provider,
    required this.statusCode,
    required String message,
  }) : super(message);

  /// e.g. 'groq', 'deepgram'.
  final String provider;

  /// HTTP status code, if applicable (e.g. not set for a malformed WS frame).
  final int? statusCode;
}

/// The SDK was misconfigured (e.g. an empty system prompt, missing required
/// provider) — caught before any network call is made.
class ConfigError extends VoiceError {
  const ConfigError(String message) : super(message);
}
