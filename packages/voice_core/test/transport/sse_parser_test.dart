import 'dart:convert';

import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

Stream<List<int>> chunksOf(List<String> chunks) {
  return Stream.fromIterable(chunks.map(utf8.encode));
}

void main() {
  group('SseParser', () {
    const parser = SseParser();

    test('parses a single complete event', () async {
      final payloads = await parser
          .parse(chunksOf(['data: hello\n\n']))
          .toList();
      expect(payloads, ['hello']);
    });

    test('parses multiple events in one chunk', () async {
      final payloads = await parser
          .parse(chunksOf(['data: one\n\ndata: two\n\n']))
          .toList();
      expect(payloads, ['one', 'two']);
    });

    test('skips the [DONE] terminator', () async {
      final payloads = await parser
          .parse(chunksOf(['data: one\n\ndata: [DONE]\n\n']))
          .toList();
      expect(payloads, ['one']);
    });

    test('ignores non-data lines (e.g. event:, blank lines)', () async {
      final payloads = await parser
          .parse(chunksOf(['event: message\ndata: hi\n\n']))
          .toList();
      expect(payloads, ['hi']);
    });

    test('handles a payload split mid-line across two chunks', () async {
      final payloads = await parser
          .parse(chunksOf(['data: hel', 'lo world\n\n']))
          .toList();
      expect(payloads, ['hello world']);
    });

    test('handles a payload split exactly at the data: prefix', () async {
      final payloads = await parser
          .parse(chunksOf(['da', 'ta: hello\n\n']))
          .toList();
      expect(payloads, ['hello']);
    });

    test('handles \\r\\n line endings', () async {
      final payloads = await parser
          .parse(chunksOf(['data: hello\r\n\r\n']))
          .toList();
      expect(payloads, ['hello']);
    });

    test('handles a multi-byte UTF-8 codepoint split across chunks', () async {
      // "café" — the 'é' (0xC3 0xA9 in UTF-8) is split mid-codepoint.
      final bytes = utf8.encode('data: café\n\n');
      final splitAt = 9; // lands inside the 2-byte 'é' sequence
      final chunk1 = bytes.sublist(0, splitAt);
      final chunk2 = bytes.sublist(splitAt);

      final payloads = await parser
          .parse(Stream.fromIterable([chunk1, chunk2]))
          .toList();
      expect(payloads, ['café']);
    });

    test('flushes a trailing payload with no terminating newline', () async {
      final payloads = await parser
          .parse(chunksOf(['data: trailing']))
          .toList();
      expect(payloads, ['trailing']);
    });

    test('emits nothing for an empty stream', () async {
      final payloads = await parser.parse(const Stream.empty()).toList();
      expect(payloads, isEmpty);
    });
  });
}
