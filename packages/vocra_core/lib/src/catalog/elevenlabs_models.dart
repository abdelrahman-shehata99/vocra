import 'catalog_entry.dart';

/// ElevenLabs TTS models, ready to pass to `VocraTts.elevenLabs(model: ...)`.
/// Only the `eleven_v3` family renders bracketed audio tags like `[laughs]`.
/// See [GroqModel] for the extensible-catalog design.
final class ElevenLabsModel implements CatalogEntry {
  const ElevenLabsModel._(this.id, this.displayName, this.tier, {this.note});

  /// Any ElevenLabs model id not (yet) in the catalog.
  const ElevenLabsModel.custom(this.id)
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

  static const flashV25 = ElevenLabsModel._(
    'eleven_flash_v2_5',
    'Flash v2.5',
    ModelTier.budget,
    note: 'default — fastest',
  );
  static const turboV25 = ElevenLabsModel._(
    'eleven_turbo_v2_5',
    'Turbo v2.5',
    ModelTier.balanced,
  );
  static const multilingualV2 = ElevenLabsModel._(
    'eleven_multilingual_v2',
    'Multilingual v2',
    ModelTier.balanced,
  );
  static const v3 = ElevenLabsModel._(
    'eleven_v3',
    'Eleven v3',
    ModelTier.flagship,
    note: '[laughs]-style audio tags, higher latency',
  );

  static const List<ElevenLabsModel> values = [
    flashV25,
    turboV25,
    multilingualV2,
    v3,
  ];

  @override
  bool operator ==(Object other) => other is ElevenLabsModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
