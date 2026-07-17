import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vocra_core/vocra_core.dart';

/// Implements [KeyStore] via `flutter_secure_storage` (spec §8.5) — optional
/// persistence for provider API keys (Keychain on iOS, Keystore on Android).
class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}
