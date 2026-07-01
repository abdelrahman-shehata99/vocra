import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voice_core/voice_core.dart';

import 'fake_websocket_channel.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('DeepgramStt', () {
    test('sampleRate is 16000', () {
      final stt = DeepgramStt(apiKey: 'key');
      expect(stt.sampleRate, 16000);
    });

    test('opens with Token auth and the documented query parameters', () async {
      late Uri capturedUri;
      late Map<String, dynamic> capturedHeaders;
      final fakeChannel = FakeWebSocketChannel();

      final stt = DeepgramStt(
        apiKey: 'secret-key',
        channelFactory: (uri, {required headers}) {
          capturedUri = uri;
          capturedHeaders = headers;
          return fakeChannel;
        },
      );

      await stt.start();

      expect(capturedUri.scheme, 'wss');
      expect(capturedUri.host, 'api.deepgram.com');
      expect(capturedUri.path, '/v1/listen');
      expect(capturedUri.queryParameters['encoding'], 'linear16');
      expect(capturedUri.queryParameters['sample_rate'], '16000');
      expect(capturedUri.queryParameters['channels'], '1');
      expect(capturedUri.queryParameters['model'], 'nova-2');
      expect(capturedUri.queryParameters['interim_results'], 'true');
      expect(capturedUri.queryParameters['punctuate'], 'true');
      expect(capturedUri.queryParameters['endpointing'], '300');
      expect(capturedUri.queryParameters['utterance_end_ms'], '1000');
      expect(capturedHeaders['Authorization'], 'Token secret-key');

      await stt.dispose();
    });

    test('sendAudio writes raw PCM16 bytes to the socket', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
      );
      await stt.start();

      final frame = Uint8List.fromList([1, 2, 3, 4]);
      stt.sendAudio(frame);

      expect(fakeChannel.sink.sent, [frame]);
      await stt.dispose();
    });

    test('emits an interim TranscriptEvent with isFinal false', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
      );
      await stt.start();

      final events = <TranscriptEvent>[];
      stt.transcripts.listen(events.add);

      fakeChannel.emit(
        jsonEncode({
          'type': 'Results',
          'is_final': false,
          'speech_final': false,
          'channel': {
            'alternatives': [
              {'transcript': 'hello wor'},
            ],
          },
        }),
      );
      await pump();

      expect(events, [
        const TranscriptEvent(
          source: TranscriptSource.user,
          text: 'hello wor',
          isFinal: false,
        ),
      ]);

      await stt.dispose();
    });

    test(
      'maps speech_final (utterance end) to isFinal true, not raw is_final',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        final stt = DeepgramStt(
          apiKey: 'key',
          channelFactory: (uri, {required headers}) => fakeChannel,
        );
        await stt.start();

        final events = <TranscriptEvent>[];
        stt.transcripts.listen(events.add);

        // is_final true but speech_final false: still mid-utterance.
        fakeChannel.emit(
          jsonEncode({
            'type': 'Results',
            'is_final': true,
            'speech_final': false,
            'channel': {
              'alternatives': [
                {'transcript': 'hello world'},
              ],
            },
          }),
        );
        // speech_final true: the utterance is actually complete.
        fakeChannel.emit(
          jsonEncode({
            'type': 'Results',
            'is_final': true,
            'speech_final': true,
            'channel': {
              'alternatives': [
                {'transcript': 'hello world'},
              ],
            },
          }),
        );
        await pump();

        expect(events.map((e) => e.isFinal).toList(), [false, true]);

        await stt.dispose();
      },
    );

    test(
      'UtteranceEnd finalizes the last transcript when no speech_final arrives',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        final stt = DeepgramStt(
          apiKey: 'key',
          channelFactory: (uri, {required headers}) => fakeChannel,
        );
        await stt.start();

        final events = <TranscriptEvent>[];
        stt.transcripts.listen(events.add);

        // A locked-in segment, but endpointing never fired speech_final.
        fakeChannel.emit(
          jsonEncode({
            'type': 'Results',
            'is_final': true,
            'speech_final': false,
            'channel': {
              'alternatives': [
                {'transcript': 'bye now'},
              ],
            },
          }),
        );
        // Silence long enough that Deepgram gives up and sends UtteranceEnd.
        fakeChannel.emit(
          jsonEncode({'type': 'UtteranceEnd', 'last_word_end': 1.23}),
        );
        await pump();

        // One interim (isFinal false) plus a synthesized final carrying the
        // last transcript, so the engine can still start a turn.
        expect(events.map((e) => (e.text, e.isFinal)).toList(), [
          ('bye now', false),
          ('bye now', true),
        ]);

        await stt.dispose();
      },
    );

    test('UtteranceEnd after speech_final does not double-emit', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
      );
      await stt.start();

      final events = <TranscriptEvent>[];
      stt.transcripts.listen(events.add);

      fakeChannel.emit(
        jsonEncode({
          'type': 'Results',
          'is_final': true,
          'speech_final': true,
          'channel': {
            'alternatives': [
              {'transcript': 'hello world'},
            ],
          },
        }),
      );
      // A trailing UtteranceEnd for the same utterance must be ignored.
      fakeChannel.emit(jsonEncode({'type': 'UtteranceEnd'}));
      await pump();

      expect(events.map((e) => e.isFinal).toList(), [true]);

      await stt.dispose();
    });

    test('ignores malformed and unrelated messages without crashing', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
      );
      await stt.start();

      final events = <TranscriptEvent>[];
      stt.transcripts.listen(events.add);

      fakeChannel.emit('not json');
      fakeChannel.emit(jsonEncode({'type': 'Metadata'}));
      await pump();

      expect(events, isEmpty);
      await stt.dispose();
    });

    test('stop() sends CloseStream', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
      );
      await stt.start();

      await stt.stop();

      expect(
        fakeChannel.sink.sent,
        contains(jsonEncode({'type': 'CloseStream'})),
      );
    });

    test('sends KeepAlive on the configured interval', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
        keepAliveInterval: const Duration(milliseconds: 20),
      );
      await stt.start();

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        fakeChannel.sink.sent,
        contains(jsonEncode({'type': 'KeepAlive'})),
      );

      await stt.dispose();
    });

    test(
      'surfaces a NetworkError on transcripts when the socket errors',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        final stt = DeepgramStt(
          apiKey: 'key',
          channelFactory: (uri, {required headers}) => fakeChannel,
        );
        await stt.start();

        final errors = <Object>[];
        stt.transcripts.listen((_) {}, onError: errors.add);

        fakeChannel.emitError(Exception('socket reset'));
        await pump();

        expect(errors, [isA<NetworkError>()]);
        await stt.dispose();
      },
    );

    test(
      'surfaces a NetworkError on transcripts when the socket closes unexpectedly',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        final stt = DeepgramStt(
          apiKey: 'key',
          channelFactory: (uri, {required headers}) => fakeChannel,
        );
        await stt.start();

        final errors = <Object>[];
        stt.transcripts.listen((_) {}, onError: errors.add);

        await fakeChannel.closeIncoming();
        await pump();

        expect(errors, [isA<NetworkError>()]);
        await stt.dispose();
      },
    );

    test('stop() does not report a spurious connection error', () async {
      final fakeChannel = FakeWebSocketChannel();
      final stt = DeepgramStt(
        apiKey: 'key',
        channelFactory: (uri, {required headers}) => fakeChannel,
      );
      await stt.start();

      final errors = <Object>[];
      stt.transcripts.listen((_) {}, onError: errors.add);

      await stt.stop();
      await fakeChannel.closeIncoming();
      await pump();

      expect(errors, isEmpty);
    });
  });
}
