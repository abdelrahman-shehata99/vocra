/// The LLM services the SDK ships adapters for. Adding a vendor requires a new
/// adapter (an SDK release), so this is a closed enum — unlike the per-vendor
/// model catalogs, which are extensible.
enum LlmVendor {
  groq('Groq'),
  openAi('OpenAI'),
  gemini('Google Gemini'),
  xai('xAI'),
  zai('Z.ai');

  const LlmVendor(this.displayName);

  /// A short human-readable label for pickers.
  final String displayName;
}

/// The text-to-speech services the SDK ships adapters for.
enum TtsVendor {
  deepgram('Deepgram'),
  elevenLabs('ElevenLabs');

  const TtsVendor(this.displayName);

  /// A short human-readable label for pickers.
  final String displayName;
}

/// The speech-to-text services the SDK ships adapters for.
enum SttVendor {
  deepgram('Deepgram');

  const SttVendor(this.displayName);

  /// A short human-readable label for pickers.
  final String displayName;
}
