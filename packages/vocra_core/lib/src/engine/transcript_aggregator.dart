import '../models/transcript_event.dart';

/// Collapses the raw stream of interim/final [TranscriptEvent]s into the
/// running list of conversation "bubbles" a UI wants to render.
///
/// The canonical merge rule: an incoming event **replaces** the trailing event
/// iff that trailing event is non-final and from the same source; otherwise it
/// is appended. So a run of interims from one speaker updates one bubble in
/// place, the final for that run replaces its own interim (rather than being
/// appended after it), and any switch of speaker — or a new run after a final —
/// starts a fresh bubble.
///
/// Pure and framework-free: [VoiceEngine] owns the stream, but this class is
/// reusable standalone (e.g. an app aggregating the raw `transcripts` stream
/// itself) and is unit-tested in isolation.
class TranscriptAggregator {
  final List<TranscriptEvent> _events = [];

  /// An unmodifiable snapshot of the aggregated conversation so far.
  List<TranscriptEvent> get events => List.unmodifiable(_events);

  /// Merges [event] per the rule above and returns the updated snapshot.
  List<TranscriptEvent> add(TranscriptEvent event) {
    if (_events.isNotEmpty &&
        !_events.last.isFinal &&
        _events.last.source == event.source) {
      _events[_events.length - 1] = event;
    } else {
      _events.add(event);
    }
    return events;
  }

  /// Drops everything — call when a new conversation starts.
  void clear() => _events.clear();
}
