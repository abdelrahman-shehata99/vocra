import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

void main() {
  group('VocraLlm', () {
    test('groq returns a GroqLlm', () {
      expect(VocraLlm.groq(apiKey: 'k'), isA<GroqLlm>());
    });
    test('openAi returns an OpenAiLlm', () {
      expect(VocraLlm.openAi(apiKey: 'k'), isA<OpenAiLlm>());
    });
    test('gemini returns a GeminiLlm', () {
      expect(VocraLlm.gemini(apiKey: 'k'), isA<GeminiLlm>());
    });
  });

  group('VocraTts', () {
    test('deepgram maps voice to the Deepgram model', () {
      final tts = VocraTts.deepgram(apiKey: 'k', voice: 'aura-luna-en');
      expect(tts, isA<DeepgramTts>());
      expect((tts as DeepgramTts).model, 'aura-luna-en');
    });

    test('elevenLabs forwards model and expressiveness knobs', () {
      final tts = VocraTts.elevenLabs(
        apiKey: 'k',
        voiceId: 'v',
        model: 'eleven_v3',
        style: 0.4,
        speakerBoost: true,
      );
      final el = tts as ElevenLabsTts;
      expect(el.voiceId, 'v');
      expect(el.modelId, 'eleven_v3');
      expect(el.style, 0.4);
      expect(el.useSpeakerBoost, isTrue);
      // eleven_v3 unlocks audio tags.
      expect(el.supportsAudioTags, isTrue);
    });
  });

  group('VocraStt', () {
    test('deepgram forwards model and language', () {
      final stt = VocraStt.deepgram(
        apiKey: 'k',
        model: 'nova-3',
        language: 'es',
      );
      expect(stt, isA<DeepgramStt>());
      expect((stt as DeepgramStt).model, 'nova-3');
      expect(stt.language, 'es');
    });
  });
}
