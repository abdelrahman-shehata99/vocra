/// Automatic session-ending rules, inspired by call-agent platforms. All are
/// optional; the default [SessionPolicies] never ends the session on its own.
///
/// When any policy fires, if [endMessage] is set the assistant speaks it as a
/// farewell (the session's last turn) before tearing down; otherwise the
/// session ends immediately. User-initiated `stop()`/`endSession()` never play
/// the farewell — only automatic ends do.
class SessionPolicies {
  const SessionPolicies({
    this.maxDuration,
    this.silenceTimeout,
    this.endPhrases = const [],
    this.endMessage,
  });

  /// Hard cap on total session length, measured from `startConversation()`.
  /// Any in-flight reply is interrupted when it elapses.
  final Duration? maxDuration;

  /// Ends the session after this much continuous user silence while listening.
  /// Reset by any user speech (including interim transcripts). A muted user
  /// still counts as silent.
  final Duration? silenceTimeout;

  /// Spoken phrases that end the session, matched case- and
  /// punctuation-insensitively against final user transcripts (the transcript
  /// equals or ends with a phrase). Choose distinctive phrases — e.g. a bare
  /// "bye" risks matching "don't say bye yet".
  final List<String> endPhrases;

  /// The farewell spoken on any automatic end (max duration / silence / end
  /// phrase). When null, automatic ends tear down immediately with no goodbye.
  final String? endMessage;

  /// Whether any automatic-end policy is configured.
  bool get hasAny =>
      maxDuration != null || silenceTimeout != null || endPhrases.isNotEmpty;
}
