/// A picker-ready catalog entry: a wire [id] plus a human [displayName] (and an
/// optional [note]). Every model/voice catalog ([GroqModel], [DeepgramVoice],
/// …) implements this, so an app can build one generic dropdown for any of them
/// from its `.values` list.
abstract interface class CatalogEntry {
  /// The wire value sent to the provider (the `model`/voice id).
  String get id;

  /// A short human-readable label for pickers.
  String get displayName;

  /// Optional extra hint (e.g. 'free tier', 'retires 2026-08-16', '[laughs] tags').
  String? get note;
}

/// A rough price/capability band, so pickers can show "cheapest vs flagship".
enum ModelTier {
  /// Cheapest / fastest.
  budget('Budget'),

  /// The sensible default band.
  balanced('Balanced'),

  /// Most capable / most expensive.
  flagship('Flagship');

  const ModelTier(this.displayName);

  /// A short human-readable label.
  final String displayName;
}
