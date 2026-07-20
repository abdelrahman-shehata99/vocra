import 'chat_message.dart';
import 'turn_metrics.dart';

/// Why a conversation session ended.
enum SessionEndReason {
  /// The app called `stop()` / `endSession()`.
  userStopped,

  /// `SessionPolicies.maxDuration` elapsed.
  maxDurationReached,

  /// `SessionPolicies.silenceTimeout` elapsed with no user speech.
  silenceTimeout,

  /// The user said one of `SessionPolicies.endPhrases`.
  endPhrase,

  /// Reserved: the engine currently recovers to listening on provider errors
  /// rather than ending, so this is never emitted in this release. Declared so
  /// exhaustive switches in app code stay valid if auto-end-on-error is added.
  error,
}

/// A summary of one completed conversation session, produced on every end path
/// (see `VocraSession.endSession` / `sessionEnded`).
class SessionReport {
  const SessionReport({
    required this.messages,
    required this.startedAt,
    required this.endedAt,
    required this.endReason,
    required this.turnCount,
    required this.turnMetrics,
  });

  /// The full user + assistant exchange, in order, **untrimmed** (unlike the
  /// LLM context window it is never capped by `maxHistoryMessages`). Never
  /// includes the system prompt.
  final List<ChatMessage> messages;

  /// When `startConversation()` was called.
  final DateTime startedAt;

  /// When the session finished tearing down.
  final DateTime endedAt;

  /// Why the session ended.
  final SessionEndReason endReason;

  /// Number of completed assistant turns (equals `turnMetrics.length`).
  final int turnCount;

  /// Latency metrics for each completed turn, in order.
  final List<TurnMetrics> turnMetrics;

  /// Wall-clock length of the session.
  Duration get duration => endedAt.difference(startedAt);

  @override
  String toString() =>
      'SessionReport(reason: $endReason, turns: $turnCount, '
      'duration: $duration, messages: ${messages.length})';
}
