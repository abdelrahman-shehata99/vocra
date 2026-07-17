import 'dart:convert';

/// Parses a raw Server-Sent Events byte stream into `data:` payload strings
/// (spec §7.4), skipping the `[DONE]` terminator emitted by OpenAI-compatible
/// APIs.
///
/// SSE events are not guaranteed to land on chunk boundaries — a single
/// `data: ...` line, or even a single UTF-8 codepoint, can be split across
/// two network reads. This buffers partial lines (and partial codepoints,
/// via [Utf8Decoder]'s stateful stream conversion) until a full line with a
/// trailing `\n` arrives.
class SseParser {
  const SseParser();

  Stream<String> parse(Stream<List<int>> byteStream) async* {
    var buffer = '';
    // `.cast<List<int>>()` re-reifies the stream's type argument as
    // `List<int>` — without it, a `Stream<Uint8List>` (e.g. from Dio) fails
    // `Utf8Decoder`'s runtime StreamTransformer<List<int>, String> check
    // even though Uint8List implements List<int>.
    final decoded = byteStream.cast<List<int>>().transform(const Utf8Decoder());
    await for (final chunk in decoded) {
      buffer += chunk;
      var newlineIndex = buffer.indexOf('\n');
      while (newlineIndex != -1) {
        final line = buffer.substring(0, newlineIndex);
        buffer = buffer.substring(newlineIndex + 1);
        final payload = _extractPayload(line);
        if (payload != null) yield payload;
        newlineIndex = buffer.indexOf('\n');
      }
    }
    final payload = _extractPayload(buffer);
    if (payload != null) yield payload;
  }

  static const _prefix = 'data:';

  String? _extractPayload(String rawLine) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (!line.startsWith(_prefix)) return null;

    var payload = line.substring(_prefix.length);
    if (payload.startsWith(' ')) {
      payload = payload.substring(1);
    }
    if (payload == '[DONE]') return null;
    return payload;
  }
}
