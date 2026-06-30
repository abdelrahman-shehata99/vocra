/// Turns a stream of partial LLM tokens into complete sentences, emitted as
/// early as possible so TTS can start before the LLM finishes (spec §6.1).
class SentenceSplitter {
  SentenceSplitter({
    this.minChars = 12,
    this.eagerMinChars = 15,
    this.eagerFallbackChars = 40,
  });

  /// Minimum trimmed sentence length to emit on a weak terminator (`.`/`…`).
  /// Strong terminators (`!`/`?`/Arabic `؟`) always emit regardless of
  /// length, to avoid sitting on an exclamation/question forever.
  final int minChars;

  /// Eager mode (see [add]'s `eager` flag): once the buffer exceeds this and
  /// no sentence terminator has appeared, split on the earliest clause
  /// boundary instead of waiting for a full sentence.
  final int eagerMinChars;

  /// Eager mode: if no clause boundary is found either, flush the whole
  /// buffer as one chunk once it exceeds this length.
  final int eagerFallbackChars;

  // Clause boundaries used by eager mode, in priority of earliest position.
  static const _clauseSeparators = [', ', '; ', ': ', '— '];

  final StringBuffer _buffer = StringBuffer();

  static const _terminators = {'.', '!', '?', '…', '؟'};
  static const _strongTerminators = {'!', '?', '؟'};

  // Common abbreviations that end in a period but are not sentence
  // boundaries. Matched case-insensitively against the text immediately
  // preceding (and including) the candidate '.'.
  static const _abbreviations = [
    'mr.',
    'mrs.',
    'ms.',
    'dr.',
    'prof.',
    'sr.',
    'jr.',
    'st.',
    'e.g.',
    'i.e.',
    'vs.',
    'etc.',
    'approx.',
    'no.',
  ];
  static final int _maxAbbreviationLength = _abbreviations
      .map((a) => a.length)
      .reduce((a, b) => a > b ? a : b);

  /// Feed a token; returns any newly completed sentences (0..n).
  ///
  /// When [eager] is true (the engine sets this only while waiting for the
  /// *first* sentence of a turn), and no real sentence boundary has appeared
  /// yet, the splitter will break early on a clause boundary so the first
  /// TTS clip can start sooner. This is a faithful port of the HTML
  /// reference's first-sentence latency optimization and materially lowers
  /// time-to-first-voice on long opening sentences.
  List<String> add(String token, {bool eager = false}) {
    _buffer.write(token);
    final sentences = _scan();
    if (sentences.isEmpty && eager) {
      final eagerSentence = _tryEagerSplit();
      if (eagerSentence != null) sentences.add(eagerSentence);
    }
    return sentences;
  }

  /// Eager fallback: emit the earliest clause (or the whole buffer once it's
  /// long enough) so the first clip isn't gated on a full sentence.
  String? _tryEagerSplit() {
    final text = _buffer.toString();
    if (text.length <= eagerMinChars) return null;

    int? best;
    for (final sep in _clauseSeparators) {
      // Require the boundary to be at least a few words in (index >= 12) so
      // we don't emit a one- or two-word fragment.
      final i = text.indexOf(sep, 12);
      if (i != -1 && (best == null || i < best)) best = i;
    }
    if (best != null) {
      final sentence = text.substring(0, best + 1).trim();
      final remainder = text.substring(best + 2);
      _buffer
        ..clear()
        ..write(remainder);
      return sentence.isEmpty ? null : sentence;
    }

    if (text.trim().length > eagerFallbackChars) {
      _buffer.clear();
      return text.trim();
    }
    return null;
  }

  /// Call when the LLM stream ends; returns any remaining buffered text.
  String? flush() {
    final remaining = _buffer.toString().trim();
    _buffer.clear();
    return remaining.isEmpty ? null : remaining;
  }

  List<String> _scan() {
    final sentences = <String>[];
    var text = _buffer.toString();
    var searchFrom = 0;

    while (true) {
      final boundaryEnd = _findBoundaryEnd(text, searchFrom);
      if (boundaryEnd == null) break;

      final candidate = text.substring(0, boundaryEnd);
      final terminatorChar = text[boundaryEnd - 1];
      final isStrong = _strongTerminators.contains(terminatorChar);
      final trimmed = candidate.trim();

      if (trimmed.length >= minChars || isStrong) {
        sentences.add(trimmed);
        text = text.substring(boundaryEnd).trimLeft();
        searchFrom = 0;
      } else {
        // Too short and not a strong terminator — keep scanning past it
        // rather than splitting on a one-word fragment.
        searchFrom = boundaryEnd;
      }
    }

    _buffer
      ..clear()
      ..write(text);
    return sentences;
  }

  /// Returns the exclusive end index of a confirmed sentence boundary
  /// starting the search at [from], or null if none is found yet.
  ///
  /// A terminator only counts once we can see whitespace after it — if it's
  /// sitting at the very end of the buffered text, we can't yet tell
  /// whether it's a real boundary (vs. e.g. the '.' in a decimal whose
  /// digits haven't arrived yet), so we wait for the next token.
  int? _findBoundaryEnd(String text, int from) {
    for (var i = from; i < text.length; i++) {
      final ch = text[i];
      if (!_terminators.contains(ch)) continue;

      final hasNext = i + 1 < text.length;
      if (!hasNext) return null; // wait for more tokens

      final next = text[i + 1];
      // A terminator immediately followed by a non-whitespace character is
      // mid-token, not a boundary — this also covers decimals like "3.14"
      // (the '.' is followed by '1', not whitespace).
      if (next.trim().isNotEmpty) continue;

      if (ch == '.' && _endsWithAbbreviation(text, i)) continue;

      return i + 1;
    }
    return null;
  }

  bool _endsWithAbbreviation(String text, int periodIndex) {
    final start = (periodIndex + 1 - _maxAbbreviationLength).clamp(
      0,
      periodIndex + 1,
    );
    final window = text.substring(start, periodIndex + 1).toLowerCase();
    return _abbreviations.any(window.endsWith);
  }
}
