/// Latency measurements for one conversation turn (spec §4). Every field is
/// `null` until the corresponding moment has actually been measured.
class TurnMetrics {
  const TurnMetrics({
    this.ttft,
    this.firstSentenceReady,
    this.firstTtsReady,
    this.timeToFirstVoice,
    this.total,
  });

  /// Time to first LLM token.
  final Duration? ttft;

  /// Time until the first complete sentence is available from the splitter.
  final Duration? firstSentenceReady;

  /// Time until the first TTS clip's bytes are ready.
  final Duration? firstTtsReady;

  /// Time until the first clip actually starts playing.
  final Duration? timeToFirstVoice;

  /// Time for the whole turn, end to end.
  final Duration? total;

  TurnMetrics copyWith({
    Duration? ttft,
    Duration? firstSentenceReady,
    Duration? firstTtsReady,
    Duration? timeToFirstVoice,
    Duration? total,
  }) {
    return TurnMetrics(
      ttft: ttft ?? this.ttft,
      firstSentenceReady: firstSentenceReady ?? this.firstSentenceReady,
      firstTtsReady: firstTtsReady ?? this.firstTtsReady,
      timeToFirstVoice: timeToFirstVoice ?? this.timeToFirstVoice,
      total: total ?? this.total,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TurnMetrics &&
          other.ttft == ttft &&
          other.firstSentenceReady == firstSentenceReady &&
          other.firstTtsReady == firstTtsReady &&
          other.timeToFirstVoice == timeToFirstVoice &&
          other.total == total);

  @override
  int get hashCode => Object.hash(
    ttft,
    firstSentenceReady,
    firstTtsReady,
    timeToFirstVoice,
    total,
  );

  @override
  String toString() =>
      'TurnMetrics(ttft: $ttft, firstSentenceReady: $firstSentenceReady, '
      'firstTtsReady: $firstTtsReady, timeToFirstVoice: $timeToFirstVoice, '
      'total: $total)';
}
