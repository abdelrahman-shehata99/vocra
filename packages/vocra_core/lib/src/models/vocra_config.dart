import '../providers/llm_provider.dart';
import '../providers/stt_transport.dart';
import '../providers/tts_provider.dart';
import 'greeting.dart';

/// Half-duplex (default, v1) suspends the mic while the AI speaks. Full
/// duplex enables barge-in and requires native echo cancellation (spec §9).
enum DuplexMode { halfDuplex, fullDuplex }

/// How eagerly a full-duplex session treats incoming speech as a barge-in.
/// Unused in [DuplexMode.halfDuplex].
enum BargeInSensitivity { relaxed, balanced, eager }

/// The consumer-facing config object (spec §4). Constructed once by the app
/// and passed to `VocraSession`/`VoiceEngine`.
class VocraConfig {
  const VocraConfig({
    required this.llm,
    required this.tts,
    required this.stt,
    required this.systemPrompt,
    this.temperature = 0.7,
    this.maxTokens = 512,
    this.maxHistoryMessages = 20,
    this.duplex = DuplexMode.halfDuplex,
    this.sensitivity = BargeInSensitivity.balanced,
    this.greeting,
    this.naturalSpeech = false,
  });

  final LlmProvider llm;
  final TtsProvider tts;
  final SttTransport stt;

  /// Persona / instructions, always kept as the first message in history.
  final String systemPrompt;

  final double temperature;
  final int maxTokens;

  /// History is trimmed to this many messages by dropping the oldest
  /// non-system messages; the system prompt is never dropped.
  final int maxHistoryMessages;

  final DuplexMode duplex;

  /// Only used when [duplex] is [DuplexMode.fullDuplex].
  final BargeInSensitivity sensitivity;

  /// How the assistant opens the conversation. Null (the default) means the
  /// user speaks first; set a [Greeting] to have the AI speak first.
  final Greeting? greeting;

  /// When true, augments [systemPrompt] with a voice-conversation style guide
  /// (brief spoken replies, contractions, natural interjections, no markdown or
  /// emojis) and — if the TTS supports them — light use of audio tags like
  /// `[laughs]`. Default false: [systemPrompt] is used verbatim.
  final bool naturalSpeech;
}
