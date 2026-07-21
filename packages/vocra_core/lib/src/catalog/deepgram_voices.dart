import 'catalog_entry.dart';

/// Deepgram Aura TTS voices, ready to pass to `VocraTts.deepgram(voice: ...)`
/// or build a picker from [values]. See [GroqModel] for the extensible-catalog
/// design; [note] carries the voice's character.
final class DeepgramVoice implements CatalogEntry {
  const DeepgramVoice._(this.id, this.displayName, {this.note});

  /// Any Deepgram voice id not (yet) in the catalog.
  const DeepgramVoice.custom(this.id) : displayName = id, note = null;

  @override
  final String id;
  @override
  final String displayName;
  @override
  final String? note;

  static const asteria = DeepgramVoice._(
    'aura-asteria-en',
    'Asteria',
    note: 'warm, natural (F)',
  );
  static const luna = DeepgramVoice._(
    'aura-luna-en',
    'Luna',
    note: 'soft, gentle (F)',
  );
  static const stella = DeepgramVoice._(
    'aura-stella-en',
    'Stella',
    note: 'clear, bright (F)',
  );
  static const athena = DeepgramVoice._(
    'aura-athena-en',
    'Athena',
    note: 'British, poised (F)',
  );
  static const hera = DeepgramVoice._(
    'aura-hera-en',
    'Hera',
    note: 'mature, confident (F)',
  );
  static const orion = DeepgramVoice._(
    'aura-orion-en',
    'Orion',
    note: 'deep, resonant (M)',
  );
  static const arcas = DeepgramVoice._(
    'aura-arcas-en',
    'Arcas',
    note: 'smooth, calm (M)',
  );
  static const perseus = DeepgramVoice._(
    'aura-perseus-en',
    'Perseus',
    note: 'bold, clear (M)',
  );
  static const angus = DeepgramVoice._(
    'aura-angus-en',
    'Angus',
    note: 'Irish, warm (M)',
  );
  static const orpheus = DeepgramVoice._(
    'aura-orpheus-en',
    'Orpheus',
    note: 'rich, expressive (M)',
  );
  static const helios = DeepgramVoice._(
    'aura-helios-en',
    'Helios',
    note: 'British, articulate (M)',
  );
  static const zeus = DeepgramVoice._(
    'aura-zeus-en',
    'Zeus',
    note: 'commanding, deep (M)',
  );

  static const List<DeepgramVoice> values = [
    asteria,
    luna,
    stella,
    athena,
    hera,
    orion,
    arcas,
    perseus,
    angus,
    orpheus,
    helios,
    zeus,
  ];

  @override
  bool operator ==(Object other) => other is DeepgramVoice && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
