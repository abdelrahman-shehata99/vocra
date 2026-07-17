import '../models/chat_message.dart';
import '../util/cancellation.dart';

/// Streams assistant text from a chat-completion endpoint (spec §5, §7.1).
abstract class LlmProvider {
  /// Streams assistant text tokens for the given history.
  /// Must stop promptly when [cancel] is triggered (R5).
  Stream<String> streamCompletion(
    List<ChatMessage> history, {
    required double temperature,
    required int maxTokens,
    required Cancellation cancel,
  });

  /// Optionally pre-establishes the network path (DNS + TCP + TLS) so the
  /// first [streamCompletion] doesn't pay the handshake (~100–300 ms). Called
  /// fire-and-forget at conversation start; implementations **must swallow all
  /// errors and never throw**. Default: no-op.
  Future<void> warmUp() async {}
}
