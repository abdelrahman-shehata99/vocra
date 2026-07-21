import 'catalog_entry.dart';

/// Z.ai GLM chat models. See [GroqModel] for the extensible-catalog design.
final class ZaiModel implements CatalogEntry {
  const ZaiModel._(this.id, this.displayName, this.tier, {this.note});

  /// Any Z.ai model id, including one newer than this SDK release.
  const ZaiModel.custom(this.id) : displayName = id, tier = null, note = null;

  @override
  final String id;
  @override
  final String displayName;
  final ModelTier? tier;
  @override
  final String? note;

  static const glm46 = ZaiModel._(
    'glm-4.6',
    'GLM-4.6',
    ModelTier.balanced,
    note: 'default — 200K context',
  );
  static const glm5Turbo = ZaiModel._(
    'glm-5-turbo',
    'GLM-5 Turbo',
    ModelTier.budget,
    note: 'fast, low-cost',
  );
  static const glm52 = ZaiModel._(
    'glm-5.2',
    'GLM-5.2',
    ModelTier.flagship,
    note: 'most capable',
  );

  static const List<ZaiModel> values = [glm46, glm5Turbo, glm52];

  @override
  bool operator ==(Object other) => other is ZaiModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
