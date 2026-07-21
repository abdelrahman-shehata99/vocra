import 'llm_provider.dart';
import 'openai_compatible_llm.dart';

/// Implements [LlmProvider] against Z.ai's GLM chat-completions endpoint, via
/// [OpenAiCompatibleLlm] (`POST https://api.z.ai/api/paas/v4/chat/completions`,
/// `Authorization: Bearer <key>`, streaming SSE — OpenAI-compatible).
///
/// Z.ai uses the older `max_tokens` field (not `max_completion_tokens`), so this
/// overrides [maxTokensField]. The default [model] is `glm-4.6`; pass any GLM
/// model id via `ZaiLlm(model: ...)`.
class ZaiLlm extends OpenAiCompatibleLlm {
  ZaiLlm({
    required super.apiKey,
    super.model = 'glm-4.6',
    super.baseUrl = 'https://api.z.ai/api/paas/v4',
    super.dio,
  });

  @override
  String get providerName => 'zai';

  @override
  String get maxTokensField => 'max_tokens';
}
