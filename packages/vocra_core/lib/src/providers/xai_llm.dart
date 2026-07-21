import 'openai_compatible_llm.dart';

/// Implements [LlmProvider] against xAI's Grok chat-completions endpoint, via
/// [OpenAiCompatibleLlm] (`POST https://api.x.ai/v1/chat/completions`,
/// `Authorization: Bearer <key>`, streaming SSE — OpenAI-compatible).
///
/// The default [model] is `grok-4.3`. Pass any Grok model id via
/// `XaiLlm(model: ...)`.
class XaiLlm extends OpenAiCompatibleLlm {
  XaiLlm({
    required super.apiKey,
    super.model = 'grok-4.3',
    super.baseUrl = 'https://api.x.ai/v1',
    super.dio,
  });

  @override
  String get providerName => 'xai';
}
