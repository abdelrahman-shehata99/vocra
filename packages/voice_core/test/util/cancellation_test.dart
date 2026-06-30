import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

void main() {
  group('Cancellation', () {
    test('starts not cancelled', () {
      final cancel = Cancellation();
      expect(cancel.isCancelled, isFalse);
    });

    test('cancel() flips isCancelled and completes whenCancelled', () async {
      final cancel = Cancellation();
      var fired = false;
      cancel.whenCancelled.then((_) => fired = true);

      cancel.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(cancel.isCancelled, isTrue);
      expect(fired, isTrue);
    });

    test('cancel() is idempotent', () {
      final cancel = Cancellation();
      cancel.cancel();
      expect(() => cancel.cancel(), returnsNormally);
      expect(cancel.isCancelled, isTrue);
    });

    test('whenCancelled resolves even if read after cancel()', () async {
      final cancel = Cancellation();
      cancel.cancel();
      await expectLater(cancel.whenCancelled, completes);
    });
  });
}
