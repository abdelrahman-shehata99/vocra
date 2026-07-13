// Public exports for voice_core (spec §2). Populated as each piece lands.

export 'src/models/chat_message.dart';
export 'src/models/turn_state.dart';
export 'src/models/transcript_event.dart';
export 'src/models/turn_metrics.dart';
export 'src/models/voice_error.dart';
export 'src/models/voice_config.dart';

export 'src/io/audio_sink.dart';
export 'src/io/mic_source.dart';
export 'src/io/key_store.dart';

export 'src/providers/llm_provider.dart';
export 'src/providers/tts_provider.dart';
export 'src/providers/stt_transport.dart';
export 'src/providers/groq_llm.dart';
export 'src/providers/gemini_llm.dart';
export 'src/providers/deepgram_tts.dart';
export 'src/providers/elevenlabs_tts.dart';
export 'src/providers/deepgram_stt.dart';

export 'src/transport/sse_parser.dart';

export 'src/engine/sentence_splitter.dart';
export 'src/engine/audio_queue.dart';
export 'src/engine/turn_machine.dart';
export 'src/engine/voice_engine.dart';

export 'src/util/cancellation.dart';
