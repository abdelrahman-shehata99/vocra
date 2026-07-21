import 'llm_provider.dart';
import 'openai_compatible_llm.dart';

/// Implements [LlmProvider] against OpenAI's chat-completions endpoint, via
/// [OpenAiCompatibleLlm] (`POST https://api.openai.com/v1/chat/completions`,
/// `Authorization: Bearer <key>`, streaming SSE).
///
/// The default [model] is `gpt-4.1-mini` — a fast, low-cost chat model, the
/// right trade-off for real-time voice. Pass any model you have access to via
/// `OpenAiLlm(model: ...)`.
class OpenAiLlm extends OpenAiCompatibleLlm {
  OpenAiLlm({
    required super.apiKey,
    super.model = 'gpt-4.1-mini',
    super.baseUrl = 'https://api.openai.com/v1',
    super.dio,
  });

  @override
  String get providerName => 'openai';
}
