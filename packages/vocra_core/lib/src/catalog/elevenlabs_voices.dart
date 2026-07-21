import 'catalog_entry.dart';

/// ElevenLabs TTS voices, ready to pass to `VocraTts.elevenLabs(voice: ...)`.
/// See [GroqModel] for the extensible-catalog design.
final class ElevenLabsVoice implements CatalogEntry {
  const ElevenLabsVoice._(this.id, this.displayName, {this.note});

  /// Any ElevenLabs voice id not (yet) in the catalog.
  const ElevenLabsVoice.custom(this.id) : displayName = id, note = null;

  @override
  final String id;
  @override
  final String displayName;
  @override
  final String? note;

  static const sarah = ElevenLabsVoice._(
    'EXAVITQu4vr4xnSDxMaL',
    'Sarah',
    note: 'soft, warm (F)',
  );
  static const rachel = ElevenLabsVoice._(
    '21m00Tcm4TlvDq8ikWAM',
    'Rachel',
    note: 'calm, clear (F)',
  );
  static const domi = ElevenLabsVoice._(
    'AZnzlk1XvdvUeBnXmlld',
    'Domi',
    note: 'strong, confident (F)',
  );
  static const elli = ElevenLabsVoice._(
    'MF3mGyEYCl7XYWbV9V6O',
    'Elli',
    note: 'youthful, friendly (F)',
  );
  static const dorothy = ElevenLabsVoice._(
    'ThT5KcBeYPX3keUQqHPh',
    'Dorothy',
    note: 'deep, narration (F)',
  );
  static const adam = ElevenLabsVoice._(
    'pNInz6obpgDQGcFmaJgB',
    'Adam',
    note: 'deep, versatile (M)',
  );
  static const sam = ElevenLabsVoice._(
    'yoZ06aMxZJJ28mfd3POQ',
    'Sam',
    note: 'smooth, professional (M)',
  );
  static const josh = ElevenLabsVoice._(
    'TxGEqnHWrfWFTfGW9XjX',
    'Josh',
    note: 'engaging, warm (M)',
  );
  static const arnold = ElevenLabsVoice._(
    'VR6AewLTigWG4xSOukaG',
    'Arnold',
    note: 'bold, commanding (M)',
  );
  static const antoni = ElevenLabsVoice._(
    'ErXwobaYiN019PkySvjV',
    'Antoni',
    note: 'friendly, casual (M)',
  );

  static const List<ElevenLabsVoice> values = [
    sarah,
    rachel,
    domi,
    elli,
    dorothy,
    adam,
    sam,
    josh,
    arnold,
    antoni,
  ];

  @override
  bool operator ==(Object other) => other is ElevenLabsVoice && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
