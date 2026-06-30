import 'package:audio_session/audio_session.dart';

/// Configures the platform audio session for a voice conversation (spec
/// §8.3): category `playAndRecord`, mode `voiceChat`, default to speaker,
/// allow Bluetooth. Exposes interruption (phone call) and route-change
/// (headphones/AirPods unplugged) events for the caller — typically
/// [VoiceSession] — to react to by pausing/resuming the conversation.
class AudioSessionSetup {
  AudioSessionSetup._(this._session);

  final AudioSession _session;

  static Future<AudioSessionSetup> configure() async {
    final session = await AudioSession.instance;
    final categoryOptions =
        AVAudioSessionCategoryOptions.defaultToSpeaker |
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.allowBluetoothA2dp;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: categoryOptions,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
    await session.setActive(true);
    return AudioSessionSetup._(session);
  }

  /// Fires when a phone call or other app interrupts (begin) or hands back
  /// (end) audio focus.
  Stream<AudioInterruptionEvent> get interruptions =>
      _session.interruptionEventStream;

  /// Fires when audio output becomes "noisy" (e.g. headphones unplugged) —
  /// the conventional UX is to pause so audio doesn't suddenly blast out of
  /// the speaker.
  Stream<void> get becomingNoisy => _session.becomingNoisyEventStream;

  Future<bool> setActive(bool active) => _session.setActive(active);
}
