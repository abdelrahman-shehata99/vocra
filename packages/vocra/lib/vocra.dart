/// The Flutter platform layer of the Vocra voice AI SDK.
///
/// This package wires the pure-Dart `vocra_core` engine to a device: microphone
/// capture, audio playback, microphone permissions, and audio-session handling.
/// It re-exports all of `vocra_core`, so a single import is enough:
///
/// ```dart
/// import 'package:vocra/vocra.dart';
///
/// final session = VocraSession(
///   config: VocraConfig(
///     llm: GroqLlm(apiKey: groqKey),
///     stt: DeepgramStt(apiKey: deepgramKey),
///     tts: DeepgramTts(apiKey: deepgramKey),
///     systemPrompt: 'You are a helpful voice assistant.',
///     greeting: const Greeting.text('Hi! How can I help?'),
///   ),
/// );
/// await session.requestPermissions();
/// await session.start();
/// ```
///
/// [VocraSession] is the app-facing entry point. Add the platform microphone
/// permission strings (iOS `NSMicrophoneUsageDescription`, Android
/// `RECORD_AUDIO`) as described in the README before calling [VocraSession.start].
library;

export 'package:vocra_core/vocra_core.dart';

export 'src/flutter_audio_sink.dart';
export 'src/flutter_mic_source.dart';
export 'src/native_aec_mic_source.dart';
export 'src/secure_key_store.dart';
export 'src/audio_session_setup.dart';
export 'src/mic_permission.dart';
export 'src/vocra_session.dart';
