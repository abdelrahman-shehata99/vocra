import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

void main() {
  group('VocraPrompt', () {
    test('plain text renders verbatim with no headings', () {
      expect(
        const VocraPrompt('You are helpful.').render(),
        'You are helpful.',
      );
    });

    test('sections render in author order under ## headings', () {
      final prompt = const VocraPrompt.sections([
        PromptSection('Persona', 'You are Riley.'),
        PromptSection('Tone', 'Be warm.'),
      ]);
      expect(
        prompt.render(),
        '## Persona\n\nYou are Riley.\n\n## Tone\n\nBe warm.',
      );
    });

    test('json section pretty-prints preserving insertion order', () {
      final prompt = const VocraPrompt.sections([
        PromptSection.json('Hours', {'mon': '9-5', 'sat': '10-2'}),
      ]);
      expect(
        prompt.render(),
        '## Hours\n\n```json\n{\n  "mon": "9-5",\n  "sat": "10-2"\n}\n```',
      );
    });

    test('jsonText embeds pre-serialized JSON verbatim', () {
      final prompt = const VocraPrompt.sections([
        PromptSection.jsonText('Raw', '{"a":1}'),
      ]);
      expect(prompt.render(), '## Raw\n\n```json\n{"a":1}\n```');
    });

    test('VocraPrompt.json composes instructions plus a context block', () {
      final prompt = VocraPrompt.json(
        {'plan': 'pro'},
        instructions: 'Use the account context.',
        title: 'Account',
      );
      expect(prompt.render(), contains('## Instructions'));
      expect(prompt.render(), contains('Use the account context.'));
      expect(prompt.render(), contains('## Account'));
      expect(prompt.render(), contains('"plan": "pro"'));
    });
  });
}
