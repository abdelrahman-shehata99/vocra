import 'package:vocra_core/vocra_core.dart';

import 'fakes.dart';

/// Yields the microtask/event queue [times] times so async engine work settles.
Future<void> pump([int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Shared test rig: a [VoiceEngine] wired to controllable fakes.
class Harness {
  Harness({
    int maxHistoryMessages = 20,
    DuplexMode duplex = DuplexMode.halfDuplex,
    BargeInSensitivity sensitivity = BargeInSensitivity.balanced,
    Greeting? greeting,
    bool naturalSpeech = false,
    String systemPrompt = 'You are a helpful assistant.',
    bool ttsSupportsAudioTags = false,
  }) : mic = FakeMicSource(),
       stt = FakeSttTransport(),
       llm = FakeLlmProvider(),
       tts = FakeTtsProvider(),
       sink = FakeAudioSink() {
    tts.supportsAudioTags = ttsSupportsAudioTags;
    config = VocraConfig(
      llm: llm,
      tts: tts,
      stt: stt,
      systemPrompt: systemPrompt,
      maxHistoryMessages: maxHistoryMessages,
      duplex: duplex,
      sensitivity: sensitivity,
      greeting: greeting,
      naturalSpeech: naturalSpeech,
    );
    engine = VoiceEngine(config, audioSink: sink, mic: mic);
  }

  final FakeMicSource mic;
  final FakeSttTransport stt;
  final FakeLlmProvider llm;
  final FakeTtsProvider tts;
  final FakeAudioSink sink;
  late final VocraConfig config;
  late final VoiceEngine engine;
}
