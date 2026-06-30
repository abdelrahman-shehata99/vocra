import 'dart:async';

import '../models/turn_state.dart';

/// Holds the current [TurnState] and enforces legal transitions (spec §6.3):
/// idle→listening, listening→thinking, thinking→speaking,
/// speaking→listening|idle, and any state→idle on stop.
class TurnMachine {
  TurnState _state = TurnState.idle;

  final StreamController<TurnState> _controller =
      StreamController<TurnState>.broadcast();

  static const Map<TurnState, Set<TurnState>> _legalTransitions = {
    TurnState.idle: {TurnState.listening},
    TurnState.listening: {TurnState.thinking, TurnState.idle},
    TurnState.thinking: {TurnState.speaking, TurnState.idle},
    TurnState.speaking: {TurnState.listening, TurnState.idle},
  };

  TurnState get state => _state;
  Stream<TurnState> get stream => _controller.stream;

  /// Applies [next] if the transition is legal; otherwise rejects it. Any
  /// state may transition to [TurnState.idle] (stop). In debug builds an
  /// illegal transition trips an assertion; in release it is silently
  /// rejected and the state is left unchanged.
  void transitionTo(TurnState next) {
    final legal =
        next == TurnState.idle || _legalTransitions[_state]!.contains(next);
    assert(legal, 'Illegal TurnState transition: $_state -> $next');
    if (!legal) return;

    _state = next;
    _controller.add(next);
  }

  Future<void> dispose() => _controller.close();
}
