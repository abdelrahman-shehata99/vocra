import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:vocra_flutter/vocra_flutter.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('SecureKeyStore', () {
    late _MockStorage storage;
    late SecureKeyStore keyStore;

    setUp(() {
      storage = _MockStorage();
      keyStore = SecureKeyStore(storage: storage);
    });

    test('read delegates to storage by key', () async {
      when(
        () => storage.read(key: 'groq_api_key'),
      ).thenAnswer((_) async => 'gsk_x');

      expect(await keyStore.read('groq_api_key'), 'gsk_x');
      verify(() => storage.read(key: 'groq_api_key')).called(1);
    });

    test('write delegates to storage by key and value', () async {
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await keyStore.write('deepgram_api_key', 'secret');
      verify(
        () => storage.write(key: 'deepgram_api_key', value: 'secret'),
      ).called(1);
    });

    test('delete delegates to storage by key', () async {
      when(
        () => storage.delete(key: any(named: 'key')),
      ).thenAnswer((_) async {});

      await keyStore.delete('groq_api_key');
      verify(() => storage.delete(key: 'groq_api_key')).called(1);
    });
  });
}
