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
}
