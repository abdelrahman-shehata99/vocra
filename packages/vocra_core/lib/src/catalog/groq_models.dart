import 'catalog_entry.dart';

/// Groq-hosted chat models, ready to pass to `VocraLlm.groq(model: ...)` or
/// build a picker from [values]. For a model not (yet) listed here, use
/// [GroqModel.custom].
///
/// Extensible by design: model line-ups change on the provider's timeline, not
/// the SDK's. Equality is by [id], so `GroqModel.custom('openai/gpt-oss-20b')`
/// equals [gptOss20b] — which keeps Flutter dropdown value-matching working.
final class GroqModel implements CatalogEntry {
  const GroqModel._(this.id, this.displayName, this.tier, {this.note});

  /// Any Groq model id, including one newer than this SDK release.
  const GroqModel.custom(this.id) : displayName = id, tier = null, note = null;

  @override
  final String id;
  @override
  final String displayName;

  /// Price/capability band; null for [GroqModel.custom].
  final ModelTier? tier;
  @override
  final String? note;

  static const gptOss20b = GroqModel._(
    'openai/gpt-oss-20b',
    'GPT-OSS 20B',
    ModelTier.budget,
    note: 'default — fast, low-cost reasoning model',
  );
  static const gptOss120b = GroqModel._(
    'openai/gpt-oss-120b',
    'GPT-OSS 120B',
    ModelTier.flagship,
  );
  static const llama33_70bVersatile = GroqModel._(
    'llama-3.3-70b-versatile',
    'Llama 3.3 70B Versatile',
    ModelTier.balanced,
  );
  static const llama31_8bInstant = GroqModel._(
    'llama-3.1-8b-instant',
    'Llama 3.1 8B Instant',
    ModelTier.budget,
    note: 'retires 2026-08-16',
  );

  /// All listed models, for building pickers.
  static const List<GroqModel> values = [
    gptOss20b,
    gptOss120b,
    llama33_70bVersatile,
    llama31_8bInstant,
  ];

  @override
  bool operator ==(Object other) => other is GroqModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
