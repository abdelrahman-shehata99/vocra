// A minimal, Flutter-free tour of the vocra_core config surface.
//
// vocra_core has no microphone or speaker of its own — those come from the
// `AudioSink` / `MicSource` interfaces (implemented by vocra_flutter on a real
// device). This example plugs in trivial stand-ins so it compiles and runs
// anywhere. It only performs a real turn if GROQ_API_KEY and DEEPGRAM_API_KEY
// are set in the environment; otherwise it just prints the wiring and exits.
//
// Run:  dart run example/main.dart
// (optionally: GROQ_API_KEY=... DEEPGRAM_API_KEY=... dart run example/main.dart)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:vocra_core/vocra_core.dart';

/// A mic that never produces audio — enough to satisfy the engine offline.
class SilentMic implements MicSource {
  final _controller = StreamController<Uint8List>.broadcast();
  @override
  int get sampleRate => 16000;
  @override
  Stream<Uint8List> get pcm16 => _controller.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
}

/// A "speaker" that just prints each clip and immediately reports it finished.
class PrintSink implements AudioSink {
  final _finished = StreamController<void>.broadcast();
  @override
  Future<void> enqueue(int index, Uint8List bytes, String format) async {
    stdout.writeln('  ▶ clip #$index (${bytes.length} bytes, $format)');
    _finished.add(null);
  }

  @override
  Stream<void> get clipFinished => _finished.stream;
  @override
  Stream<double> get amplitude => const Stream.empty();
  @override
  Future<void> stopNow() async {}
  @override
  Future<void> dispose() async => _finished.close();
}

Future<void> main() async {
  final groqKey = Platform.environment['GROQ_API_KEY'];
  final deepgramKey = Platform.environment['DEEPGRAM_API_KEY'];

  final config = VocraConfig(
    llm: GroqLlm(apiKey: groqKey ?? 'missing'),
    stt: DeepgramStt(apiKey: deepgramKey ?? 'missing'),
    tts: DeepgramTts(apiKey: deepgramKey ?? 'missing'),
    systemPrompt: 'You are a warm, concise voice assistant.',
    naturalSpeech: true,
    greeting: const Greeting.text('Hey! What can I do for you?'),
  );

  final engine = VoiceEngine(config, audioSink: PrintSink(), mic: SilentMic());
  engine.transcripts.listen((e) {
    if (e.isFinal) stdout.writeln('[${e.source.name}] ${e.text}');
  });
  engine.errors.listen((e) => stderr.writeln('error: ${e.message}'));

  if (groqKey == null || deepgramKey == null) {
    stdout.writeln(
      'Set GROQ_API_KEY and DEEPGRAM_API_KEY to run a real turn. '
      'Config wired successfully; exiting.',
    );
    return;
  }

  await engine.startConversation();
  await engine.sendText('Tell me a fun fact about the ocean.');
  await Future<void>.delayed(const Duration(seconds: 5));
  await engine.stopConversation();
  await engine.dispose();
}
