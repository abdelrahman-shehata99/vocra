import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/transcript_event.dart';
import '../models/voice_error.dart';
import 'stt_transport.dart';

/// Opens a [WebSocketChannel] to [uri] with the given request [headers].
/// Injectable so tests can swap in a fake channel instead of a real socket.
typedef WebSocketChannelFactory =
    WebSocketChannel Function(Uri uri, {required Map<String, dynamic> headers});

WebSocketChannel _defaultChannelFactory(
  Uri uri, {
  required Map<String, dynamic> headers,
}) {
  return IOWebSocketChannel.connect(uri, headers: headers);
}

/// Implements [SttTransport] against Deepgram's streaming speech-to-text
/// WebSocket endpoint (spec §7.2).
///
/// Endpoint, query parameters, auth header, and response shape verified
/// against Deepgram's current docs as of writing: `wss://api.deepgram.com/v1/listen`,
/// `Authorization: Token <key>` (not `Bearer` — spec §13), and
/// `channel.alternatives[0].transcript` / `is_final` / `speech_final` on
/// `"type": "Results"` messages.
///
/// Deepgram exposes two different "final" signals: `is_final` (this
/// segment's wording is locked in, but the user may still be talking) and
/// `speech_final` (the user has stopped — endpointing fired). Spec §6.4
/// step 2 triggers the LLM turn on "STT final transcript (utterance end /
/// speech_final)", so [TranscriptEvent.isFinal] here is deliberately wired
/// to `speech_final`, not the lower-level `is_final` — that's the signal
/// the engine actually needs to decide an utterance is complete.
class DeepgramStt implements SttTransport {
  DeepgramStt({
    required String apiKey,
    this.model = 'nova-2',
    String baseUrl = 'wss://api.deepgram.com/v1/listen',
    WebSocketChannelFactory channelFactory = _defaultChannelFactory,
    Duration keepAliveInterval = const Duration(seconds: 8),
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl,
       _channelFactory = channelFactory,
       _keepAliveInterval = keepAliveInterval;

  final String _apiKey;
  final String model;
  final String _baseUrl;
  final WebSocketChannelFactory _channelFactory;
  final Duration _keepAliveInterval;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepAliveTimer;

  final StreamController<TranscriptEvent> _transcriptsController =
      StreamController<TranscriptEvent>.broadcast();

  @override
  int get sampleRate => 16000;

  @override
  Stream<TranscriptEvent> get transcripts => _transcriptsController.stream;

  @override
  Future<void> start() async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'encoding': 'linear16',
        'sample_rate': '$sampleRate',
        'channels': '1',
        'model': model,
        'interim_results': 'true',
        'punctuate': 'true',
        'endpointing': '300',
      },
    );

    final channel = _channelFactory(
      uri,
      headers: {'Authorization': 'Token $_apiKey'},
    );
    _channel = channel;
    await channel.ready;

    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object _, StackTrace __) {
        // A transport-level WS error (dropped connection, etc). [transcripts]
        // is a Stream<TranscriptEvent>, but stream error events aren't
        // constrained by the data type, so we can surface a typed
        // VoiceError on it directly rather than going quiet.
        if (!_transcriptsController.isClosed) {
          _transcriptsController.addError(
            const NetworkError('Deepgram STT connection lost.'),
          );
        }
      },
      onDone: () {
        // The server closed the connection without us calling stop() —
        // same treatment as a transport error.
        if (!_transcriptsController.isClosed) {
          _transcriptsController.addError(
            const NetworkError('Deepgram STT connection closed unexpectedly.'),
          );
        }
      },
    );

    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      _channel?.sink.add(jsonEncode({'type': 'KeepAlive'}));
    });
  }

  @override
  void sendAudio(Uint8List pcm16) {
    _channel?.sink.add(pcm16);
  }

  @override
  Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _channel?.sink.add(jsonEncode({'type': 'CloseStream'}));
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  Future<void> dispose() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    await _transcriptsController.close();
  }

  void _onMessage(dynamic message) {
    if (message is! String) return; // Deepgram sends JSON text frames

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(message) as Map<String, dynamic>;
    } on FormatException {
      return;
    }

    final channel = json['channel'] as Map<String, dynamic>?;
    if (channel == null) return;

    final alternatives = channel['alternatives'] as List<dynamic>?;
    if (alternatives == null || alternatives.isEmpty) return;

    final transcript =
        (alternatives.first as Map<String, dynamic>?)?['transcript'] as String?;
    if (transcript == null) return;

    final speechFinal = json['speech_final'] as bool? ?? false;
    _transcriptsController.add(
      TranscriptEvent(
        source: TranscriptSource.user,
        text: transcript,
        isFinal: speechFinal,
      ),
    );
  }
}
