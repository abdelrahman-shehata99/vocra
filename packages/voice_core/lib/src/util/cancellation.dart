import 'dart:async';

/// Cooperative cancellation token (spec §6.5), used in place of the
/// browser's `AbortController`. Adapters check [isCancelled] between chunks
/// and race [whenCancelled] against their I/O so an in-flight LLM/TTS/STT
/// call stops promptly (R5).
class Cancellation {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _cancelled;

  /// Completes when [cancel] is called. Already-completed if cancelled
  /// before this getter is first read.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}
