import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

List<String> feed(SentenceSplitter splitter, List<String> tokens) {
  final out = <String>[];
  for (final token in tokens) {
    out.addAll(splitter.add(token));
  }
  return out;
}

void main() {
  group('SentenceSplitter', () {
    test('emits a long sentence on a weak terminator', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, ['This is a long enough sentence. ']);
      expect(out, ['This is a long enough sentence.']);
    });

    test('does not split a short fragment on a weak terminator', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, ['Ok. ']);
      expect(out, isEmpty);
      expect(splitter.flush(), 'Ok.');
    });

    test('emits immediately on a strong terminator regardless of length', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, ['Wow! ']);
      expect(out, ['Wow!']);
    });

    test('splits a sentence streamed across many small tokens', () {
      final splitter = SentenceSplitter();
      final tokens = 'The quick brown fox jumps. '.split('');
      final out = feed(splitter, tokens);
      expect(out, ['The quick brown fox jumps.']);
    });

    test('a sentence boundary split across exactly two chunks', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, [
        'This is a long enough sentence',
        '. And here is more. ',
      ]);
      expect(out, ['This is a long enough sentence.', 'And here is more.']);
    });

    test('does not split on common abbreviations', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, [
        'Dr. Smith met Mr. Jones at the e.g. conference today. ',
      ]);
      expect(out, ['Dr. Smith met Mr. Jones at the e.g. conference today.']);
    });

    test('does not split a decimal number', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, [
        'Pi is roughly 3.14159 and that is well known. ',
      ]);
      expect(out, ['Pi is roughly 3.14159 and that is well known.']);
    });

    test('does not split a decimal number streamed across tokens', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, [
        'The price is 3',
        '.',
        '14 dollars exactly today. ',
      ]);
      expect(out, ['The price is 3.14 dollars exactly today.']);
    });

    test('handles Arabic strong terminator (؟)', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, ['كيف حالك؟ ']);
      expect(out, ['كيف حالك؟']);
    });

    test('flush returns remaining buffered text', () {
      final splitter = SentenceSplitter();
      feed(splitter, ['No trailing terminator here']);
      expect(splitter.flush(), 'No trailing terminator here');
    });

    test('flush returns null when buffer is empty', () {
      final splitter = SentenceSplitter();
      expect(splitter.flush(), isNull);
    });

    test(
      'flush after a full sentence already emitted only returns the rest',
      () {
        final splitter = SentenceSplitter();
        final out = feed(splitter, [
          'This is a long enough first sentence. ',
          'And a trailing fragment',
        ]);
        expect(out, ['This is a long enough first sentence.']);
        expect(splitter.flush(), 'And a trailing fragment');
      },
    );

    test('multiple complete sentences in a single token', () {
      final splitter = SentenceSplitter();
      final out = feed(splitter, [
        'First sentence here. Second sentence here. ',
      ]);
      expect(out, ['First sentence here.', 'Second sentence here.']);
    });
  });

  group('SentenceSplitter eager mode', () {
    test('splits on the earliest clause boundary when eager', () {
      final splitter = SentenceSplitter();
      // No terminator yet, but a comma past index 12 and buffer > 15 chars.
      final out = splitter.add(
        'A vector database stores data, and it is fast',
        eager: true,
      );
      expect(out, ['A vector database stores data,']);
    });

    test('does not eager-split when not flagged eager', () {
      final splitter = SentenceSplitter();
      final out = splitter.add('A vector database stores data, and it is fast');
      expect(out, isEmpty);
    });

    test('eager falls back to whole buffer past the fallback length', () {
      final splitter = SentenceSplitter();
      // No clause boundary and no terminator, but long enough to flush.
      final out = splitter.add(
        'this is a long clauseless run of words with no breaks at all here',
        eager: true,
      );
      expect(out, [
        'this is a long clauseless run of words with no breaks at all here',
      ]);
    });

    test('eager does not fire on a short buffer', () {
      final splitter = SentenceSplitter();
      final out = splitter.add('short, bit', eager: true);
      expect(out, isEmpty);
    });

    test('a real terminator still takes priority over eager clause split', () {
      final splitter = SentenceSplitter();
      final out = splitter.add('Yes, absolutely correct. ', eager: true);
      expect(out, ['Yes, absolutely correct.']);
    });
  });
}
