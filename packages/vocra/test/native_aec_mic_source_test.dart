import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocra/vocra.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('voice_flutter/aec_mic');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('NativeAecMicSource.isAvailable', () {
    test('returns true when the native side reports available', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'isAvailable';
      });
      expect(await NativeAecMicSource.isAvailable(), isTrue);
    });

    test('returns false when the native side reports unavailable', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await NativeAecMicSource.isAvailable(), isFalse);
    });

    test('returns false when the plugin is missing (no handler)', () async {
      // No mock handler registered -> MissingPluginException, swallowed to false.
      expect(await NativeAecMicSource.isAvailable(), isFalse);
    });

    test('returns false on a PlatformException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await NativeAecMicSource.isAvailable(), isFalse);
    });
  });
}
