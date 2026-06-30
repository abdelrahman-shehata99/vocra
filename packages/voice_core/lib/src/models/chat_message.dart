/// A single role in a conversation history (spec §4).
enum MessageRole { system, user, assistant }

/// One message in the conversation history sent to the LLM (spec §4).
class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final MessageRole role;
  final String content;

  ChatMessage copyWith({MessageRole? role, String? content}) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage && other.role == role && other.content == content);

  @override
  int get hashCode => Object.hash(role, content);

  @override
  String toString() => 'ChatMessage(role: $role, content: $content)';
}
