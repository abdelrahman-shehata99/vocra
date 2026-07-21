import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

void main() {
  group('catalogs', () {
    final catalogs = <String, List<CatalogEntry>>{
      'GroqModel': GroqModel.values,
      'OpenAiModel': OpenAiModel.values,
      'GeminiModel': GeminiModel.values,
      'XaiModel': XaiModel.values,
      'ZaiModel': ZaiModel.values,
      'DeepgramVoice': DeepgramVoice.values,
      'ElevenLabsVoice': ElevenLabsVoice.values,
      'ElevenLabsModel': ElevenLabsModel.values,
      'DeepgramSttModel': DeepgramSttModel.values,
    };

    catalogs.forEach((name, values) {
      test('$name has unique, non-empty ids and display names', () {
        expect(values, isNotEmpty);
        for (final e in values) {
          expect(e.id, isNotEmpty, reason: '$name entry with empty id');
          expect(e.displayName, isNotEmpty);
        }
        final ids = values.map((e) => e.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: '$name has dupes');
      });
    });

    test('custom entries equal each other and catalog constants by id', () {
      // Dropdown value-matching depends on == by id.
      expect(const GroqModel.custom('x'), const GroqModel.custom('x'));
      expect(const GroqModel.custom('openai/gpt-oss-20b'), GroqModel.gptOss20b);
      expect(const ElevenLabsModel.custom('eleven_v3'), ElevenLabsModel.v3);
    });

    test('ElevenLabs v3 catalog id maps to a tag-supporting TTS', () {
      final tts = ElevenLabsTts(apiKey: 'k', modelId: ElevenLabsModel.v3.id);
      expect(tts.supportsAudioTags, isTrue);
    });
  });
}
