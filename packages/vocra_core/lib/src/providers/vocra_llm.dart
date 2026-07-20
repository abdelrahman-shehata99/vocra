import 'gemini_llm.dart';
import 'groq_llm.dart';
import 'llm_provider.dart';
import 'openai_llm.dart';

/// Ready-made LLM providers, one factory per service. This is the easy way to
/// set `VocraConfig.llm`:
///
/// ```dart
/// llm: VocraLlm.openAi(apiKey: openAiKey),
/// ```
///
/// Each factory takes only that provider's common options. For advanced knobs
/// (custom base URL, injected Dio) construct the underlying adapter
/// ([GroqLlm], [OpenAiLlm], [GeminiLlm]) directly — they implement the same
/// [LlmProvider] and plug into `VocraConfig.llm` too.
abstract final class VocraLlm {
  /// Groq (fast, low-cost). Default model `openai/gpt-oss-20b`.
  static LlmProvider groq({
    required String apiKey,
    String model = 'openai/gpt-oss-20b',
  }) => GroqLlm(apiKey: apiKey, model: model);

  /// OpenAI. Default model `gpt-4.1-mini`.
  static LlmProvider openAi({
    required String apiKey,
    String model = 'gpt-4.1-mini',
  }) => OpenAiLlm(apiKey: apiKey, model: model);

  /// Google Gemini. Default model `gemini-2.5-flash`.
  static LlmProvider gemini({
    required String apiKey,
    String model = 'gemini-2.5-flash',
  }) => GeminiLlm(apiKey: apiKey, model: model);
}
