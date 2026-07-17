/// Rewrites one sentence of LLM output into speakable text for TTS.
///
/// LLM replies routinely contain markdown (`**bold**`, `` `code` ``, bullets),
/// emojis, and — when prompted for expressiveness — bracketed stage directions
/// or audio tags like `[laughs]`. Read aloud verbatim, these become "asterisk
/// asterisk", "open bracket laughs close bracket", and mangled symbols. This
/// normalizer strips them so only speakable words reach the TTS provider.
///
/// It is applied ONLY to the text sent to TTS. Transcript events and
/// conversation history keep the original, unmodified text.
///
/// [normalize] may return an empty string (e.g. an emoji-only sentence); the
/// caller must drop empties without consuming a playback slot.
class SpeechTextNormalizer {
  const SpeechTextNormalizer({required this.stripAudioTags});

  /// When true, bracketed tags like `[laughs]` are removed (the active TTS
  /// can't render them). When false they are kept, on the assumption the TTS
  /// understands them (e.g. ElevenLabs' `eleven_v3` models).
  final bool stripAudioTags;

  // Fenced code blocks: ```lang\n...\n``` — dropped entirely.
  static final RegExp _codeFence = RegExp(r'```[\s\S]*?```');
  static final RegExp _strayFence = RegExp('```');
  // Inline code: `code` -> code
  static final RegExp _inlineCode = RegExp(r'`([^`]*)`');
  // Images: ![alt](url) -> '' (dropped; must run before links).
  static final RegExp _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
  // Links: [text](url) -> text (must run before audio-tag stripping so link
  // text survives).
  static final RegExp _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
  // Bold/italic with asterisks: *x*, **x**, ***x*** -> x
  static final RegExp _asterisk = RegExp(r'(\*{1,3})(\S(?:.*?\S)?)\1');
  // Emphasis with underscores: _x_, __x__ -> x. \b keeps snake_case intact.
  static final RegExp _underscore = RegExp(r'\b_{1,2}([^_]+)_{1,2}\b');
  // Strikethrough: ~~x~~ -> x
  static final RegExp _strike = RegExp(r'~~(.+?)~~');
  // Line-leading markers: headings, block quotes, bullets, numbered lists.
  static final RegExp _lineLead = RegExp(
    r'^\s{0,3}(?:#{1,6}\s+|>\s+|[-*+]\s+|\d+[.)]\s+)',
    multiLine: true,
  );
  // Bracketed audio tags / stage directions: [laughs], [sighs], etc.
  // Links have already been unwrapped, so remaining brackets are tags.
  static final RegExp _bracketTag = RegExp(r'\[[^\]\n]{1,40}\]');
  // Emoji and related codepoints: pictographs, variation selector-16, ZWJ,
  // regional-indicator flags, skin-tone modifiers, keycap.
  static final RegExp _emoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    r'\u{FE0F}\u{200D}\u{1F1E6}-\u{1F1FF}\u{1F3FB}-\u{1F3FF}\u{20E3}]',
    unicode: true,
  );
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Returns the speakable form of [text]. May be empty.
  String normalize(String text) {
    var out = text;
    out = out.replaceAll(_codeFence, ' ');
    out = out.replaceAllMapped(_inlineCode, (m) => m.group(1) ?? '');
    out = out.replaceAll(_image, '');
    out = out.replaceAllMapped(_link, (m) => m.group(1) ?? '');
    out = out.replaceAllMapped(_asterisk, (m) => m.group(2) ?? '');
    out = out.replaceAllMapped(_underscore, (m) => m.group(1) ?? '');
    out = out.replaceAllMapped(_strike, (m) => m.group(1) ?? '');
    out = out.replaceAll(_lineLead, '');
    if (stripAudioTags) out = out.replaceAll(_bracketTag, '');
    out = out.replaceAll(_strayFence, '');
    out = out.replaceAll(_emoji, '');
    out = out.replaceAll(_whitespace, ' ');
    return out.trim();
  }
}
