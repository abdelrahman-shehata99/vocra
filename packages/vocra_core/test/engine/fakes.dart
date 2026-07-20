import 'dart:async';
import 'dart:typed_data';

import 'package:vocra_core/vocra_core.dart';

class FakeAudioSink implements AudioSink {
  final List<int> enqueuedIndexes = [];
  int stopNowCalls = 0;

  final StreamController<void> _clipFinishedController =
      StreamController<void>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  @override
  Future<void> enqueue(int index, Uint8List bytes, String format) async {
    enqueuedIndexes.add(index);
    // Auto-finish shortly after so tests don't need to manually drive
    // playback completion for every clip.
    scheduleMicrotask(() => _clipFinishedController.add(null));
  }

  @override
  Future<void> stopNow() async {
    stopNowCalls++;
  }

  @override
  Stream<double> get amplitude => _amplitudeController.stream;

  @override
  Stream<void> get clipFinished => _clipFinishedController.stream;

  @override
  Future<void> dispose() async {
    await _clipFinishedController.close();
    await _amplitudeController.close();
  }
}

class FakeMicSource implements MicSource {
  final StreamController<Uint8List> _pcm16Controller =
      StreamController<Uint8List>.broadcast();

  bool started = false;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;

  /// When set, [resume] throws this — simulates a mic that fails to restart
  /// after the AI's turn (e.g. the platform recorder refusing the format).
  Object? resumeError;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Stream<Uint8List> get pcm16 => _pcm16Controller.stream;

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    final error = resumeError;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  int get sampleRate => 16000;

  void emit(Uint8List frame) => _pcm16Controller.add(frame);
}

class FakeSttTransport implements SttTransport {
  final StreamController<TranscriptEvent> _transcriptsController =
      StreamController<TranscriptEvent>.broadcast();
  final List<Uint8List> sentAudio = [];
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  void sendAudio(Uint8List pcm16) => sentAudio.add(pcm16);

  @override
  Stream<TranscriptEvent> get transcripts => _transcriptsController.stream;

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    await _transcriptsController.close();
  }

  @override
  int get sampleRate => 16000;

  void emitFinal(String text) => _transcriptsController.add(
    TranscriptEvent(source: TranscriptSource.user, text: text, isFinal: true),
  );

  void emitInterim(String text) => _transcriptsController.add(
    TranscriptEvent(source: TranscriptSource.user, text: text, isFinal: false),
  );

  void emitConnectionError(Object error) =>
      _transcriptsController.addError(error);
}

class FakeLlmProvider implements LlmProvider {
  final List<List<ChatMessage>> historySnapshots = [];
  StreamController<String>? _controller;
  Cancellation? lastCancel;
  int warmUpCalls = 0;

  /// When set, [warmUp] throws it — to prove start() survives a bad provider.
  Object? warmUpError;

  @override
  Stream<String> streamCompletion(
    List<ChatMessage> history, {
    required double temperature,
    required int maxTokens,
    required Cancellation cancel,
  }) {
    historySnapshots.add(List.of(history));
    lastCancel = cancel;
    final controller = StreamController<String>();
    _controller = controller;
    return controller.stream;
  }

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
    if (warmUpError != null) throw warmUpError!;
  }

  void pushToken(String token) => _controller?.add(token);

  Future<void> endStream() async {
    await _controller?.close();
  }

  void failWith(Object error) {
    _controller?.addError(error);
  }
}

class FakeTtsProvider implements TtsProvider {
  final List<String> synthesizedText = [];
  Future<Uint8List> Function(String text)? handler;
  int warmUpCalls = 0;

  @override
  String get audioFormat => 'mp3';

  @override
  bool supportsAudioTags = false;

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
  }

  @override
  Future<Uint8List> synthesize(String text, {required Cancellation cancel}) {
    synthesizedText.add(text);
    if (handler != null) return handler!(text);
    return Future.value(Uint8List.fromList(text.codeUnits));
  }
}
