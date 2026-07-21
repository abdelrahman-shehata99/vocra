import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vocra_core/vocra_core.dart';

/// Persists provider API keys in platform-secure storage via
/// `flutter_secure_storage` — Keychain on iOS, Keystore on Android.
///
/// This is optional: [VocraConfig] takes provider instances directly, so an
/// app can source keys however it likes (a backend, `--dart-define`, etc.).
/// Use [SecureKeyStore] when you want to cache user-entered keys on-device
/// between launches. Pick stable, app-unique [name]s for each key (e.g.
/// `'groq_api_key'`). Never hard-code real keys in source or commit them.
///
/// The [storage] parameter is injectable so tests can substitute an in-memory
/// fake.
class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Returns the value stored under [name], or null if absent.
  @override
  Future<String?> read(String name) => _storage.read(key: name);

  /// Stores [value] under [name], overwriting any existing value.
  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  /// Removes any value stored under [name].
  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}
