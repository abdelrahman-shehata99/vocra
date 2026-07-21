import '../catalog/gemini_models.dart';
import '../catalog/groq_models.dart';
import '../catalog/openai_models.dart';
import '../catalog/xai_models.dart';
import '../catalog/zai_models.dart';
import 'gemini_llm.dart';
import 'groq_llm.dart';
import 'llm_provider.dart';
import 'openai_llm.dart';
import 'xai_llm.dart';
import 'zai_llm.dart';

/// Ready-made LLM providers, one factory per service. This is the easy way to
/// set `VocraConfig.llm`:
///
/// ```dart
/// llm: VocraLlm.openAi(apiKey: openAiKey, model: OpenAiModel.gpt41Mini),
/// ```
///
/// Each factory takes a typed model from that provider's catalog (build a
/// picker from e.g. `GroqModel.values`, or use `GroqModel.custom('id')` for a
/// model not yet listed). For advanced knobs (custom base URL, injected Dio)
/// construct the underlying adapter ([GroqLlm], [OpenAiLlm], [GeminiLlm],
/// [XaiLlm], [ZaiLlm]) directly — they implement the same [LlmProvider] and
/// plug into `VocraConfig.llm` too.
abstract final class VocraLlm {
  /// Groq (fast, low-cost).
  static LlmProvider groq({
    required String apiKey,
    GroqModel model = GroqModel.gptOss20b,
  }) => GroqLlm(apiKey: apiKey, model: model.id);

  /// OpenAI.
  static LlmProvider openAi({
    required String apiKey,
    OpenAiModel model = OpenAiModel.gpt41Mini,
  }) => OpenAiLlm(apiKey: apiKey, model: model.id);

  /// Google Gemini.
  static LlmProvider gemini({
    required String apiKey,
    GeminiModel model = GeminiModel.flash25,
  }) => GeminiLlm(apiKey: apiKey, model: model.id);

  /// xAI Grok.
  static LlmProvider xai({
    required String apiKey,
    XaiModel model = XaiModel.grok43,
  }) => XaiLlm(apiKey: apiKey, model: model.id);

  /// Z.ai GLM.
  static LlmProvider zai({
    required String apiKey,
    ZaiModel model = ZaiModel.glm46,
  }) => ZaiLlm(apiKey: apiKey, model: model.id);
}
