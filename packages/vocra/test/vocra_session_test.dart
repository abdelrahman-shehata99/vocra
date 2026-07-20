import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vocra/vocra.dart';

class _MockPermissionHandler extends Mock
    with MockPlatformInterfaceMixin
    implements PermissionHandlerPlatform {}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VocraSession buildSession() => VocraSession(
    config: VocraConfig(
      llm: _NoopLlm(),
      tts: _NoopTts(),
      stt: _NoopStt(),
      systemPrompt: 'test',
    ),
  );

  // VocraSession builds a real FlutterMicSource (record's AudioRecorder) in its
  // constructor, which calls the record plugin channel. Stub it so construction
  // works headless; the re-entrancy guard is what's under test here.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('VocraSession.start re-entrancy', () {
    late _MockPermissionHandler permissions;

    setUp(() {
      permissions = _MockPermissionHandler();
      PermissionHandlerPlatform.instance = permissions;
      messenger.setMockMethodCallHandler(recordChannel, (call) async => null);
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(recordChannel, null);
    });

    test('two rapid start() calls request permission only once', () async {
      when(
        () => permissions.requestPermissions([Permission.microphone]),
      ).thenAnswer(
        (_) async => {Permission.microphone: PermissionStatus.denied},
      );
      final session = buildSession();
      final errors = <VoiceError>[];
      session.errors.listen(errors.add);

      // Fire both without awaiting the first: the synchronous _starting guard
      // must stop the second from slipping through.
      final a = session.start();
      final b = session.start();
      await Future.wait([a, b]);
      await Future<void>.delayed(Duration.zero);

      verify(
        () => permissions.requestPermissions([Permission.microphone]),
      ).called(1);
      // Denied permission surfaces exactly one ConfigError, not two.
      expect(errors.whereType<ConfigError>(), hasLength(1));

      await session.dispose();
    });
  });

  group('VocraSession pass-throughs', () {
    setUp(() {
      messenger.setMockMethodCallHandler(recordChannel, (call) async => null);
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(recordChannel, null);
    });

    test('mute/unmute/isMuted delegate to the engine', () async {
      final session = buildSession();
      expect(session.isMuted, isFalse);
      session.mute();
      expect(session.isMuted, isTrue);
      session.unmute();
      expect(session.isMuted, isFalse);
      await session.dispose();
    });

    test('interrupt is safe to call before a turn is in flight', () async {
      final session = buildSession();
      // idle -> interrupt is a no-op, must not throw.
      await session.interrupt();
      await session.dispose();
    });

    test('messages stream is exposed', () async {
      final session = buildSession();
      expect(session.messages, isA<Stream<List<TranscriptEvent>>>());
      await session.dispose();
    });
  });
}
