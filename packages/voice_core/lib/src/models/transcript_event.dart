/// Who produced a [TranscriptEvent] (spec §4).
enum TranscriptSource { user, assistant }

/// An interim or final transcript chunk from STT (user) or the spoken
/// reply text (assistant), as emitted on [VoiceEngine.transcripts] (spec §4).
class TranscriptEvent {
  const TranscriptEvent({
    required this.source,
    required this.text,
    required this.isFinal,
  });

  final TranscriptSource source;
  final String text;
  final bool isFinal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptEvent &&
          other.source == source &&
          other.text == text &&
          other.isFinal == isFinal);

  @override
  int get hashCode => Object.hash(source, text, isFinal);

  @override
  String toString() =>
      'TranscriptEvent(source: $source, isFinal: $isFinal, text: $text)';
}
