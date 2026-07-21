import 'catalog_entry.dart';

/// Google Gemini chat models. See [GroqModel] for the extensible-catalog design.
final class GeminiModel implements CatalogEntry {
  const GeminiModel._(this.id, this.displayName, this.tier, {this.note});

  /// Any Gemini model id, including one newer than this SDK release.
  const GeminiModel.custom(this.id)
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

  static const flash25Lite = GeminiModel._(
    'gemini-2.5-flash-lite',
    'Gemini 2.5 Flash-Lite',
    ModelTier.budget,
  );
  static const flash25 = GeminiModel._(
    'gemini-2.5-flash',
    'Gemini 2.5 Flash',
    ModelTier.balanced,
    note: 'default',
  );
  static const pro25 = GeminiModel._(
    'gemini-2.5-pro',
    'Gemini 2.5 Pro',
    ModelTier.flagship,
  );
  static const flash20 = GeminiModel._(
    'gemini-2.0-flash',
    'Gemini 2.0 Flash',
    ModelTier.budget,
  );

  static const List<GeminiModel> values = [
    flash25Lite,
    flash25,
    pro25,
    flash20,
  ];

  @override
  bool operator ==(Object other) => other is GeminiModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
