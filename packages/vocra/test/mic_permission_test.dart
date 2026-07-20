import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vocra/vocra.dart';

class _MockPermissionHandler extends Mock
    with MockPlatformInterfaceMixin
    implements PermissionHandlerPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MicPermission mapping', () {
    late _MockPermissionHandler platform;

    setUp(() {
      platform = _MockPermissionHandler();
      PermissionHandlerPlatform.instance = platform;
    });

    void stubRequest(PermissionStatus status) {
      when(
        () => platform.requestPermissions([Permission.microphone]),
      ).thenAnswer((_) async => {Permission.microphone: status});
    }

    void stubCheck(PermissionStatus status) {
      when(
        () => platform.checkPermissionStatus(Permission.microphone),
      ).thenAnswer((_) async => status);
    }

    test('granted maps to granted', () async {
      stubRequest(PermissionStatus.granted);
      expect(
        await const MicPermission().request(),
        MicPermissionStatus.granted,
      );
    });

    test('limited and provisional map to granted', () async {
      stubCheck(PermissionStatus.limited);
      expect(await const MicPermission().check(), MicPermissionStatus.granted);

      stubCheck(PermissionStatus.provisional);
      expect(await const MicPermission().check(), MicPermissionStatus.granted);
    });

    test('restricted maps to permanentlyDenied', () async {
      stubCheck(PermissionStatus.restricted);
      expect(
        await const MicPermission().check(),
        MicPermissionStatus.permanentlyDenied,
      );
    });

    test('permanentlyDenied maps to permanentlyDenied', () async {
      stubRequest(PermissionStatus.permanentlyDenied);
      expect(
        await const MicPermission().request(),
        MicPermissionStatus.permanentlyDenied,
      );
    });

    test('denied maps to denied', () async {
      stubRequest(PermissionStatus.denied);
      expect(await const MicPermission().request(), MicPermissionStatus.denied);
    });
  });
}
