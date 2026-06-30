import 'package:permission_handler/permission_handler.dart';

/// Simplified mic permission state surfaced to the app (spec §8.4).
enum MicPermissionStatus { granted, denied, permanentlyDenied }

/// Mic permission flow via `permission_handler` (spec §8.4).
class MicPermission {
  const MicPermission();

  Future<MicPermissionStatus> check() async {
    return _map(await Permission.microphone.status);
  }

  Future<MicPermissionStatus> request() async {
    return _map(await Permission.microphone.request());
  }

  MicPermissionStatus _map(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
      case PermissionStatus.provisional:
        return MicPermissionStatus.granted;
      case PermissionStatus.permanentlyDenied:
      case PermissionStatus.restricted:
        return MicPermissionStatus.permanentlyDenied;
      case PermissionStatus.denied:
        return MicPermissionStatus.denied;
    }
  }
}
