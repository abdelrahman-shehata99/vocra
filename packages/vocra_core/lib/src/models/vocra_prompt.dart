import 'dart:convert';

/// A structured system prompt that renders deterministically to a single system
/// message. Use it instead of `VocraConfig.systemPrompt` when you want multiple
/// named sections or embedded JSON context:
///
/// ```dart
/// prompt: VocraPrompt.sections([
///   PromptSection('Persona', 'You are Riley, a friendly scheduler.'),
///   PromptSection.json('Business hours', {'mon-fri': '9-5', 'sat': '10-2'}),
/// ]),
/// ```
///
/// IO-free: to include JSON from a file or asset, load it yourself (e.g.
/// `rootBundle.loadString`) and pass the contents to [PromptSection.jsonText].
final class VocraPrompt {
  /// Verbatim prompt text, rendered with no headings.
  const VocraPrompt(String text) : _text = text, _sections = null;

  /// Named sections rendered in order, each under a `## Title` heading.
  const VocraPrompt.sections(List<PromptSection> sections)
    : _text = null,
      _sections = sections;

  /// Convenience: an optional instructions paragraph plus one JSON context
  /// block under [title].
  factory VocraPrompt.json(
    Map<String, Object?> data, {
    String? instructions,
    String title = 'Context',
  }) => VocraPrompt.sections([
    if (instructions != null) PromptSection('Instructions', instructions),
    PromptSection.json(title, data),
  ]);

  final String? _text;
  final List<PromptSection>? _sections;

  /// The composed prompt text.
  String render() {
    final text = _text;
    if (text != null) return text;
    return _sections!.map((s) => s.render()).join('\n\n');
  }
}

/// One section of a [VocraPrompt.sections] prompt.
sealed class PromptSection {
  const PromptSection._();

  /// A `## title` heading followed by [body].
  const factory PromptSection(String title, String body) = TextPromptSection;

  /// A `## title` heading followed by [data] pretty-printed inside a ```json
  /// fence (map insertion order preserved).
  const factory PromptSection.json(String title, Map<String, Object?> data) =
      JsonPromptSection;

  /// A `## title` heading followed by pre-serialized [json] embedded verbatim
  /// inside a ```json fence — for JSON loaded from a file or asset.
  const factory PromptSection.jsonText(String title, String json) =
      JsonTextPromptSection;

  String render();
}

class TextPromptSection extends PromptSection {
  const TextPromptSection(this.title, this.body) : super._();
  final String title;
  final String body;
  @override
  String render() => '## $title\n\n$body';
}

class JsonPromptSection extends PromptSection {
  const JsonPromptSection(this.title, this.data) : super._();
  final String title;
  final Map<String, Object?> data;
  @override
  String render() =>
      '## $title\n\n```json\n'
      '${const JsonEncoder.withIndent('  ').convert(data)}\n```';
}

class JsonTextPromptSection extends PromptSection {
  const JsonTextPromptSection(this.title, this.json) : super._();
  final String title;
  final String json;
  @override
  String render() => '## $title\n\n```json\n$json\n```';
}
