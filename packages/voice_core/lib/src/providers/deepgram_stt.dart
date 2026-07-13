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

  /// Accumulated text of the current utterance: every `is_final` segment
  /// concatenated in order. A single spoken utterance is frequently split by
  /// Deepgram into MULTIPLE `is_final` results before `speech_final` arrives,
  /// so the full utterance is the concatenation of them all — NOT just the
  /// last one (per Deepgram's docs: "Do not use speech_final alone... long
  /// utterances may have multiple is_final responses"). Emitting only the
  /// last segment was the cause of the user being "heard only sometimes" /
  /// truncated. Flushed (emitted as a final [TranscriptEvent]) on
  /// `speech_final` or, as a fallback, on `UtteranceEnd`.
  String _utteranceBuffer = '';

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
        // Fallback end-of-utterance signal: Deepgram emits an `UtteranceEnd`
        // message after this many ms of silence when endpointing alone didn't
        // produce a `speech_final`. Without it, an utterance that never gets a
        // `speech_final` would never trigger a turn (see _onMessage).
        'utterance_end_ms': '1000',
      },
    );

    // ignore: avoid_print
    print('[vocra] DeepgramStt: connecting WS -> $uri');
    final channel = _channelFactory(
      uri,
      headers: {'Authorization': 'Token $_apiKey'},
    );
    _channel = channel;
    // Bound the connection wait so a network stall surfaces as a typed error
    // instead of hanging the whole start() forever.
    await channel.ready.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const NetworkError(
        'Deepgram STT connection timed out after 10s.',
      ),
    );
    // ignore: avoid_print
    print('[vocra] DeepgramStt: WS ready (connected)');

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
    // ignore: avoid_print
    print(
      '[vocra] DeepgramStt raw msg: '
      '${message is String ? (message.length > 220 ? message.substring(0, 220) : message) : message.runtimeType}',
    );
    if (message is! String) return; // Deepgram sends JSON text frames

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(message) as Map<String, dynamic>;
    } on FormatException {
      return;
    }

    // `UtteranceEnd` is the fallback end-of-speech signal (fires after
    // `utterance_end_ms` of silence when endpointing didn't produce a
    // `speech_final`). It carries no transcript, so flush whatever we've
    // accumulated. If `speech_final` already flushed it, the buffer is empty
    // and this is a harmless no-op (no double-trigger). Per Deepgram's
    // recommended end-of-speech logic.
    if (json['type'] == 'UtteranceEnd') {
      _flushUtterance();
      return;
    }

    final channel = json['channel'] as Map<String, dynamic>?;
    if (channel == null) return;
    final alternatives = channel['alternatives'] as List<dynamic>?;
    if (alternatives == null || alternatives.isEmpty) return;
    final transcript =
        (alternatives.first as Map<String, dynamic>?)?['transcript'] as String?;
    if (transcript == null) return;

    final segment = transcript.trim();
    final isFinalSegment = json['is_final'] as bool? ?? false;
    final speechFinal = json['speech_final'] as bool? ?? false;

    // A finalized segment is locked in — append it to the utterance buffer.
    if (isFinalSegment && segment.isNotEmpty) {
      _utteranceBuffer = _utteranceBuffer.isEmpty
          ? segment
          : '$_utteranceBuffer $segment';
    }

    if (speechFinal) {
      // End of utterance: emit the FULL accumulated text as final.
      _flushUtterance();
    } else {
      // Still mid-utterance: emit a running interim (everything finalized so
      // far, plus the current not-yet-final partial) for live UI / barge-in.
      final partial = isFinalSegment ? '' : segment;
      final running = [
        _utteranceBuffer,
        partial,
      ].where((s) => s.isNotEmpty).join(' ').trim();
      if (running.isNotEmpty) {
        _emit(running, isFinal: false);
      }
    }
  }

  /// Emits the accumulated utterance as a final [TranscriptEvent] and resets
  /// the buffer. No-op if nothing has accumulated.
  void _flushUtterance() {
    final full = _utteranceBuffer.trim();
    _utteranceBuffer = '';
    if (full.isNotEmpty) {
      // ignore: avoid_print
      print('[vocra] DeepgramStt: utterance FINAL -> "$full"');
      _emit(full, isFinal: true);
    }
  }

  void _emit(String text, {required bool isFinal}) {
    if (_transcriptsController.isClosed) return;
    _transcriptsController.add(
      TranscriptEvent(
        source: TranscriptSource.user,
        text: text,
        isFinal: isFinal,
      ),
    );
  }
}
