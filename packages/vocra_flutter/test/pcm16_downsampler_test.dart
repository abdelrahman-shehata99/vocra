import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocra_flutter/src/pcm16_downsampler.dart';

Uint8List pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
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
  group('Pcm16Downsampler', () {
    test('48k -> 16k decimates a ramp exactly 3:1', () {
      final ds = Pcm16Downsampler(inputRate: 48000, outputRate: 16000);
      final out = ds.process(pcm(List.generate(48, (i) => i)));
      // Every third sample, starting from the first real one.
      expect(samplesOf(out), List.generate(16, (i) => i * 3));
    });

    test('carries state across frame boundaries without glitches', () {
      final ds = Pcm16Downsampler(inputRate: 48000, outputRate: 16000);
      final all = <int>[];
      // Same ramp as above, split into unequal chunks.
      final ramp = List.generate(48, (i) => i);
      for (final chunk in [
        ramp.sublist(0, 7),
        ramp.sublist(7, 30),
        ramp.sublist(30),
      ]) {
        all.addAll(samplesOf(ds.process(pcm(chunk))));
      }
      expect(all, List.generate(16, (i) => i * 3));
    });

    test('44.1k -> 16k produces the right output count over many frames', () {
      final ds = Pcm16Downsampler(inputRate: 44100, outputRate: 16000);
      var outSamples = 0;
      const framesIn = 100;
      const frameLen = 441; // 10 ms at 44.1 kHz
      for (var i = 0; i < framesIn; i++) {
        outSamples += ds.process(pcm(List.filled(frameLen, 1000))).length ~/ 2;
      }
      // 44100 samples in -> ~16000 out (10 ms * 100 frames = 1 s of audio).
      expect(outSamples, inInclusiveRange(15999, 16001));
    });

    test('a DC signal stays at the same level', () {
      final ds = Pcm16Downsampler(inputRate: 44100, outputRate: 16000);
      final out = samplesOf(ds.process(pcm(List.filled(441, -12345))));
      expect(out, isNotEmpty);
      expect(out.toSet(), {-12345});
    });

    test('empty and odd-length frames are handled defensively', () {
      final ds = Pcm16Downsampler(inputRate: 48000, outputRate: 16000);
      expect(ds.process(Uint8List(0)), isEmpty);
      expect(ds.process(Uint8List(1)), isEmpty); // lone odd byte -> no sample
    });
  });
}
