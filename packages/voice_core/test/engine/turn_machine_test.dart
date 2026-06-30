import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

void main() {
  group('TurnMachine', () {
    test('starts idle', () {
      final machine = TurnMachine();
      expect(machine.state, TurnState.idle);
    });

    test('walks the full legal turn cycle', () async {
      final machine = TurnMachine();
      final emitted = <TurnState>[];
      machine.stream.listen(emitted.add);

      machine.transitionTo(TurnState.listening);
      machine.transitionTo(TurnState.thinking);
      machine.transitionTo(TurnState.speaking);
      machine.transitionTo(TurnState.listening);
      await Future<void>.delayed(Duration.zero);

      expect(machine.state, TurnState.listening);
      expect(emitted, [
        TurnState.listening,
        TurnState.thinking,
        TurnState.speaking,
        TurnState.listening,
      ]);
    });

    test('speaking can go straight to idle (stop)', () {
      final machine = TurnMachine()
        ..transitionTo(TurnState.listening)
        ..transitionTo(TurnState.thinking)
        ..transitionTo(TurnState.speaking)
        ..transitionTo(TurnState.idle);

      expect(machine.state, TurnState.idle);
    });

    test('any state can transition to idle', () {
      for (final start in [
        TurnState.listening,
        TurnState.thinking,
        TurnState.speaking,
      ]) {
        final machine = TurnMachine();
        // Walk to `start` via legal transitions.
        if (start.index >= TurnState.listening.index) {
          machine.transitionTo(TurnState.listening);
        }
        if (start.index >= TurnState.thinking.index) {
          machine.transitionTo(TurnState.thinking);
        }
        if (start.index >= TurnState.speaking.index) {
          machine.transitionTo(TurnState.speaking);
        }
        expect(machine.state, start);

        machine.transitionTo(TurnState.idle);
        expect(machine.state, TurnState.idle);
      }
    });

    test('allows idle -> thinking (typed-input entry path)', () {
      final machine = TurnMachine();
      machine.transitionTo(TurnState.thinking);
      expect(machine.state, TurnState.thinking);
    });

    test('rejects an illegal transition (idle -> speaking)', () {
      final machine = TurnMachine();
      expect(
        () => machine.transitionTo(TurnState.speaking),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects skipping listening -> speaking', () {
      final machine = TurnMachine()..transitionTo(TurnState.listening);
      expect(
        () => machine.transitionTo(TurnState.speaking),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
