import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:vocra_flutter/vocra_flutter.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

Uint8List pcmRamp(int n) {
  final data = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    data.setInt16(i * 2, i, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<int> samplesOf(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i < bytes.length ~/ 2; i++)
      data.getInt16(i * 2, Endian.little),
  ];
}

void main() {
  setUpAll(() {
    registerFallbackValue(const RecordConfig(encoder: AudioEncoder.pcm16bits));
  });

  group('FlutterMicSource sample-rate fallback', () {
    late _MockAudioRecorder recorder;

    setUp(() {
      recorder = _MockAudioRecorder();
      when(() => recorder.hasPermission()).thenAnswer((_) async => true);
      when(() => recorder.stop()).thenAnswer((_) async => null);
    });

    test('streams frames unchanged when 16 kHz capture is accepted', () async {
      final frames = StreamController<Uint8List>();
      when(
        () => recorder.startStream(any()),
      ).thenAnswer((_) async => frames.stream);

      final mic = FlutterMicSource(recorder: recorder);
      final received = <Uint8List>[];
      mic.pcm16.listen(received.add);
      await mic.start();

      frames.add(pcmRamp(48));
      await Future<void>.delayed(Duration.zero);

      expect(mic.sampleRate, 16000);
      expect(received, hasLength(1));
      expect(samplesOf(received.single), List.generate(48, (i) => i));

      final config =
          verify(() => recorder.startStream(captureAny())).captured.single
              as RecordConfig;
      expect(config.sampleRate, 16000);
      await frames.close();
    });

    test('falls back to 48 kHz and downsamples when 16 kHz capture is refused '
        '(iOS simulator "Format conversion is not possible")', () async {
      final frames = StreamController<Uint8List>();
      when(() => recorder.startStream(any())).thenAnswer((invocation) async {
        final config = invocation.positionalArguments.single as RecordConfig;
        if (config.sampleRate == 16000) {
          throw PlatformException(
            code: 'record',
            message: 'Failed to start recording',
            details: 'Format conversion is not possible.',
          );
        }
        expect(config.sampleRate, 48000);
        return frames.stream;
      });

      final mic = FlutterMicSource(recorder: recorder);
      final received = <Uint8List>[];
      mic.pcm16.listen(received.add);
      await mic.start();

      // A 48-sample ramp at 48 kHz must come out as 16 samples at 16 kHz.
      frames.add(pcmRamp(48));
      await Future<void>.delayed(Duration.zero);

      expect(mic.sampleRate, 16000, reason: 'output contract is fixed');
      expect(received, hasLength(1));
      expect(samplesOf(received.single), List.generate(16, (i) => i * 3));
      await frames.close();
    });

    test('rethrows the platform error when every rate is refused', () async {
      when(() => recorder.startStream(any())).thenThrow(
        PlatformException(code: 'record', message: 'no input device'),
      );

      final mic = FlutterMicSource(recorder: recorder);
      await expectLater(mic.start(), throwsA(isA<PlatformException>()));
    });

    test('pause fully stops capture and resume restarts it', () async {
      when(
        () => recorder.startStream(any()),
      ).thenAnswer((_) async => const Stream<Uint8List>.empty());

      final mic = FlutterMicSource(recorder: recorder);
      await mic.start();
      await mic.pause();
      verify(() => recorder.stop()).called(1);
      await mic.resume();
      verify(() => recorder.startStream(any())).called(2);
    });
  });
}
