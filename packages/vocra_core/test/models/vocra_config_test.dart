import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

class _NoopLlm implements LlmProvider {
  @override
  Stream<String> streamCompletion(
    List<ChatMessage> history, {
    required double temperature,
    required int maxTokens,
    required Cancellation cancel,
  }) => const Stream.empty();
  @override
  Future<void> warmUp() async {}
}

class _NoopTts implements TtsProvider {
  @override
  String get audioFormat => 'mp3';
  @override
  bool get supportsAudioTags => false;
  @override
  Future<void> warmUp() async {}
  @override
  Future<Uint8List> synthesize(
    String text, {
    required Cancellation cancel,
  }) async => Uint8List(0);
}

class _NoopStt implements SttTransport {
  @override
  int get sampleRate => 16000;
  @override
  Stream<TranscriptEvent> get transcripts => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  void sendAudio(Uint8List pcm16) {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

VocraConfig build({String? systemPrompt, VocraPrompt? prompt}) => VocraConfig(
  llm: _NoopLlm(),
  tts: _NoopTts(),
  stt: _NoopStt(),
  systemPrompt: systemPrompt,
  prompt: prompt,
);

void main() {
  group('VocraConfig prompt exclusivity', () {
    test('accepts a plain systemPrompt', () {
      expect(build(systemPrompt: 'hi'), isA<VocraConfig>());
    });

    test('accepts a structured prompt', () {
      expect(build(prompt: const VocraPrompt('hi')), isA<VocraConfig>());
    });

    test('throws when neither systemPrompt nor prompt is set', () {
      expect(build, throwsA(isA<AssertionError>()));
    });

    test('throws when both systemPrompt and prompt are set', () {
      expect(
        () => build(systemPrompt: 'a', prompt: const VocraPrompt('b')),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
