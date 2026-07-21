import 'catalog_entry.dart';

/// OpenAI chat models. See [GroqModel] for the extensible-catalog design.
final class OpenAiModel implements CatalogEntry {
  const OpenAiModel._(this.id, this.displayName, this.tier, {this.note});

  /// Any OpenAI model id, including one newer than this SDK release.
  const OpenAiModel.custom(this.id)
    : displayName = id,
      tier = null,
      note = null;

  @override
  final String id;
  @override
  final String displayName;
  final ModelTier? tier;
  @override
  final String? note;

  static const gpt41Nano = OpenAiModel._(
    'gpt-4.1-nano',
    'GPT-4.1 Nano',
    ModelTier.budget,
    note: 'cheapest, fastest',
  );
  static const gpt41Mini = OpenAiModel._(
    'gpt-4.1-mini',
    'GPT-4.1 Mini',
    ModelTier.balanced,
    note: 'default',
  );
  static const gpt41 = OpenAiModel._('gpt-4.1', 'GPT-4.1', ModelTier.flagship);

  static const List<OpenAiModel> values = [gpt41Nano, gpt41Mini, gpt41];

  @override
  bool operator ==(Object other) => other is OpenAiModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
