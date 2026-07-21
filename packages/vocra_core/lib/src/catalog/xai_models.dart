import 'catalog_entry.dart';

/// xAI Grok chat models. See [GroqModel] for the extensible-catalog design.
final class XaiModel implements CatalogEntry {
  const XaiModel._(this.id, this.displayName, this.tier, {this.note});

  /// Any xAI model id, including one newer than this SDK release.
  const XaiModel.custom(this.id) : displayName = id, tier = null, note = null;

  @override
  final String id;
  @override
  final String displayName;
  final ModelTier? tier;
  @override
  final String? note;

  static const grok43 = XaiModel._(
    'grok-4.3',
    'Grok 4.3',
    ModelTier.balanced,
    note: 'default',
  );
  static const grok420Fast = XaiModel._(
    'grok-4.20-0309-non-reasoning',
    'Grok 4.20 (fast)',
    ModelTier.budget,
    note: 'non-reasoning, low latency',
  );
  static const grok45 = XaiModel._(
    'grok-4.5',
    'Grok 4.5',
    ModelTier.flagship,
    note: 'most capable',
  );

  static const List<XaiModel> values = [grok43, grok420Fast, grok45];

  @override
  bool operator ==(Object other) => other is XaiModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
