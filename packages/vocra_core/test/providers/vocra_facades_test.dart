import 'package:test/test.dart';
import 'package:vocra_core/vocra_core.dart';

void main() {
  group('VocraLlm', () {
    test('groq returns a GroqLlm with the catalog model id', () {
      final llm = VocraLlm.groq(
        apiKey: 'k',
        model: GroqModel.llama33_70bVersatile,
      );
      expect(llm, isA<GroqLlm>());
      expect((llm as GroqLlm).model, 'llama-3.3-70b-versatile');
    });
    test('openAi returns an OpenAiLlm', () {
      expect(VocraLlm.openAi(apiKey: 'k'), isA<OpenAiLlm>());
    });
    test('gemini returns a GeminiLlm with the catalog model id', () {
      final llm = VocraLlm.gemini(apiKey: 'k', model: GeminiModel.pro25);
      expect(llm, isA<GeminiLlm>());
      expect((llm as GeminiLlm).model, 'gemini-2.5-pro');
    });
    test('xai returns an XaiLlm', () {
      expect(VocraLlm.xai(apiKey: 'k'), isA<XaiLlm>());
    });
    test('zai returns a ZaiLlm', () {
      expect(VocraLlm.zai(apiKey: 'k'), isA<ZaiLlm>());
    });
    test('a custom model id is forwarded verbatim', () {
      final llm = VocraLlm.groq(
        apiKey: 'k',
        model: const GroqModel.custom('some-new-model'),
      );
      expect((llm as GroqLlm).model, 'some-new-model');
    });
  });

  group('VocraTts', () {
    test('deepgram maps the voice to the Deepgram model', () {
      final tts = VocraTts.deepgram(apiKey: 'k', voice: DeepgramVoice.luna);
      expect((tts as DeepgramTts).model, 'aura-luna-en');
    });

    test('elevenLabs forwards voice, model, and expressiveness knobs', () {
      final tts = VocraTts.elevenLabs(
        apiKey: 'k',
        voice: ElevenLabsVoice.adam,
        model: ElevenLabsModel.v3,
        style: 0.4,
        speakerBoost: true,
      );
      final el = tts as ElevenLabsTts;
      expect(el.voiceId, 'pNInz6obpgDQGcFmaJgB');
      expect(el.modelId, 'eleven_v3');
      expect(el.style, 0.4);
      expect(el.useSpeakerBoost, isTrue);
      expect(el.supportsAudioTags, isTrue);
    });
  });

  group('VocraStt', () {
    test('deepgram forwards the model and language', () {
      final stt = VocraStt.deepgram(
        apiKey: 'k',
        model: DeepgramSttModel.nova3,
        language: 'es',
      );
      expect((stt as DeepgramStt).model, 'nova-3');
      expect(stt.language, 'es');
    });
  });

  group('adapter defaults match catalog defaults', () {
    // Pins the string default baked into each adapter to its catalog default,
    // so the two can't silently drift.
    test('LLM adapter default model == catalog default id', () {
      expect(GroqLlm(apiKey: 'k').model, GroqModel.gptOss20b.id);
      expect(OpenAiLlm(apiKey: 'k').model, OpenAiModel.gpt41Mini.id);
      expect(GeminiLlm(apiKey: 'k').model, GeminiModel.flash25.id);
      expect(XaiLlm(apiKey: 'k').model, XaiModel.grok43.id);
      expect(ZaiLlm(apiKey: 'k').model, ZaiModel.glm46.id);
    });
    test('TTS/STT adapter defaults == catalog defaults', () {
      expect(DeepgramTts(apiKey: 'k').model, DeepgramVoice.asteria.id);
      expect(ElevenLabsTts(apiKey: 'k').voiceId, ElevenLabsVoice.sarah.id);
      expect(ElevenLabsTts(apiKey: 'k').modelId, ElevenLabsModel.flashV25.id);
      expect(DeepgramStt(apiKey: 'k').model, DeepgramSttModel.nova2.id);
    });
  });
}
