/// Optional secure persistence for provider API keys (spec §5, §8.5).
abstract class KeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);
}
