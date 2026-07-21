import 'catalog_entry.dart';

/// Deepgram speech-to-text models, ready to pass to
/// `VocraStt.deepgram(model: ...)`. See [GroqModel] for the extensible-catalog
/// design.
final class DeepgramSttModel implements CatalogEntry {
  const DeepgramSttModel._(this.id, this.displayName, {this.note});

  /// Any Deepgram STT model id not (yet) in the catalog.
  const DeepgramSttModel.custom(this.id) : displayName = id, note = null;

  @override
  final String id;
  @override
  final String displayName;
  @override
  final String? note;

  static const nova2 = DeepgramSttModel._('nova-2', 'Nova-2', note: 'default');
  static const nova3 = DeepgramSttModel._(
    'nova-3',
    'Nova-3',
    note: 'best for multilingual',
  );

  static const List<DeepgramSttModel> values = [nova2, nova3];

  @override
  bool operator ==(Object other) => other is DeepgramSttModel && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}
