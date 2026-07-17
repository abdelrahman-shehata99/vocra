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

    test('endpointing and utterance_end_ms are configurable', () async {
      late Uri capturedUri;
      final fakeChannel = FakeWebSocketChannel();

      final stt = DeepgramStt(
        apiKey: 'key',
        endpointing: const Duration(milliseconds: 150),
        utteranceEnd: const Duration(milliseconds: 1500),
        channelFactory: (uri, {required headers}) {
          capturedUri = uri;
          return fakeChannel;
        },
      );

      await stt.start();

      expect(capturedUri.queryParameters['endpointing'], '150');
      expect(capturedUri.queryParameters['utterance_end_ms'], '1500');

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
      'accumulates multiple is_final segments into the full final utterance',
      () async {
        // Deepgram splits a longer utterance into several is_final results
        // before speech_final. The final event must contain the WHOLE
        // utterance, not just the last segment (the "heard only sometimes" /
        // truncation bug).
        final fakeChannel = FakeWebSocketChannel();
        final stt = DeepgramStt(
          apiKey: 'key',
          channelFactory: (uri, {required headers}) => fakeChannel,
        );
        await stt.start();

        final finals = <String>[];
        stt.transcripts
            .where((e) => e.isFinal)
            .listen((e) => finals.add(e.text));

        void emitResults({
          required String transcript,
          required bool isFinal,
          required bool speechFinal,
        }) {
          fakeChannel.emit(
            jsonEncode({
              'type': 'Results',
              'is_final': isFinal,
              'speech_final': speechFinal,
              'channel': {
                'alternatives': [
                  {'transcript': transcript},
                ],
              },
            }),
          );
        }

        // Segment 1 finalizes (mid-utterance, no speech_final yet).
        emitResults(
          transcript: 'what is the weather',
          isFinal: true,
          speechFinal: false,
        );
        // Segment 2 finalizes and ends the utterance.
        emitResults(
          transcript: 'like in san francisco today',
          isFinal: true,
          speechFinal: true,
        );
        await pump();

        expect(finals, [
          'what is the weather like in san francisco today',
        ]);

        await stt.dispose();
      },
    );

    test(
      'UtteranceEnd flushes the full accumulation, not just the last segment',
      () async {
        final fakeChannel = FakeWebSocketChannel();
        final stt = DeepgramStt(
          apiKey: 'key',
          channelFactory: (uri, {required headers}) => fakeChannel,
        );
        await stt.start();

        final finals = <String>[];
        stt.transcripts
            .where((e) => e.isFinal)
            .listen((e) => finals.add(e.text));

        void emitFinalSegment(String t) => fakeChannel.emit(
          jsonEncode({
            'type': 'Results',
            'is_final': true,
            'speech_final': false,
            'channel': {
              'alternatives': [
                {'transcript': t},
              ],
            },
          }),
        );

        emitFinalSegment('turn on the');
        emitFinalSegment('living room lights');
        // No speech_final; UtteranceEnd fires instead.
        fakeChannel.emit(
          jsonEncode({'type': 'UtteranceEnd', 'last_word_end': 3.2}),
        );
        await pump();

        expect(finals, ['turn on the living room lights']);

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
