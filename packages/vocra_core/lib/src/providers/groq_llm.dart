import 'llm_provider.dart';
import 'openai_compatible_llm.dart';

/// Implements [LlmProvider] against Groq's OpenAI-compatible chat-completions
/// endpoint (spec §7.1), via [OpenAiCompatibleLlm].
///
/// The default [model] is Groq's `openai/gpt-oss-20b`. The previous default
/// `llama-3.1-8b-instant` was deprecated by Groq on 2026-06-17 and is **retired
/// on 2026-08-16**, so it is no longer a safe default. `gpt-oss-20b` is a
/// reasoning model; for voice latency this adapter automatically sends
/// `reasoning_effort: 'low'` and `include_reasoning: false` for any
/// `openai/gpt-oss*` model so it doesn't "think" out loud before the first
/// spoken word. Consumers can pin any model via `GroqLlm(model: ...)`. See
/// console.groq.com/docs/reasoning.
class GroqLlm extends OpenAiCompatibleLlm {
  GroqLlm({
    required super.apiKey,
    super.model = 'openai/gpt-oss-20b',
    super.baseUrl = 'https://api.groq.com/openai/v1',
    super.dio,
  });

  @override
  String get providerName => 'groq';

  /// Groq's `openai/gpt-oss*` models are reasoning models that accept the
  /// `reasoning_effort` / `include_reasoning` parameters; other Groq models
  /// (e.g. the Llama family) reject them.
  bool get _isGptOss => model.startsWith('openai/gpt-oss');

  @override
  Map<String, Object?> get extraRequestFields => _isGptOss
      ? const {'reasoning_effort': 'low', 'include_reasoning': false}
      : const {};
}
