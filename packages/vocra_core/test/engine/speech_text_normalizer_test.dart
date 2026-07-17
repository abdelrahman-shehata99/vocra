import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

void main() {
  group('SpeechTextNormalizer', () {
    const stripTags = SpeechTextNormalizer(stripAudioTags: true);
    const keepTags = SpeechTextNormalizer(stripAudioTags: false);

    test(
      'strips bold, italic, and inline code markers but keeps their text',
      () {
        expect(
          stripTags.normalize('That is **really** `super` _nice_ work'),
          'That is really super nice work',
        );
      },
    );

    test('strips markdown links keeping the link text, and drops images', () {
      expect(
        stripTags.normalize('See [the docs](https://x.y) now'),
        'See the docs now',
      );
      expect(
        stripTags.normalize('Look ![alt text](https://img.png) here'),
        'Look here',
      );
    });

    test('strips leading header, bullet, and quote markers', () {
      expect(stripTags.normalize('# Heading'), 'Heading');
      expect(stripTags.normalize('- a bullet'), 'a bullet');
      expect(stripTags.normalize('> quoted'), 'quoted');
      expect(stripTags.normalize('1. first'), 'first');
    });

    test('strips emojis, variation selectors, and ZWJ sequences', () {
      expect(stripTags.normalize('Great job 🎉'), 'Great job');
      expect(stripTags.normalize('family 👨‍👩‍👧 time'), 'family time');
      expect(stripTags.normalize('thumbs 👍🏽 up'), 'thumbs up');
    });

    test('strips bracketed audio tags when stripAudioTags is true', () {
      expect(
        stripTags.normalize('Well [laughs] that is funny'),
        'Well that is funny',
      );
    });

    test('keeps bracketed audio tags when stripAudioTags is false', () {
      expect(
        keepTags.normalize('Well [laughs] that is funny'),
        'Well [laughs] that is funny',
      );
    });

    test(
      'returns empty for a sentence that is only emoji, an image, or a tag',
      () {
        expect(stripTags.normalize('🎉🎉🎉'), isEmpty);
        expect(stripTags.normalize('![a picture](https://x.png)'), isEmpty);
        expect(stripTags.normalize('[sighs]'), isEmpty);
      },
    );

    test('leaves plain prose, snake_case, and decimals untouched', () {
      expect(
        stripTags.normalize('The value_of_pi is about 3.14 today'),
        'The value_of_pi is about 3.14 today',
      );
    });

    test('collapses whitespace left behind by stripping', () {
      expect(stripTags.normalize('Nice   👍   work'), 'Nice work');
    });
  });
}
