import 'dart:async';

import '../io/audio_sink.dart';
import '../io/mic_source.dart';
import '../models/chat_message.dart';
import '../models/greeting.dart';
import '../models/transcript_event.dart';
import '../models/turn_metrics.dart';
import '../models/turn_state.dart';
import '../models/vocra_config.dart';
import '../models/voice_error.dart';
import '../providers/llm_provider.dart';
import '../providers/stt_transport.dart';
import '../providers/tts_provider.dart';
import '../util/cancellation.dart';
import 'audio_queue.dart';
import 'sentence_splitter.dart';
import 'speech_text_normalizer.dart';
import 'transcript_aggregator.dart';
import 'turn_machine.dart';

/// The pure-Dart orchestrator that wires STT, the LLM, TTS, and ordered
/// audio playback into one half-duplex conversation loop (spec §6.4).
class VoiceEngine {
  VoiceEngine(this._config, {required AudioSink audioSink, required this._mic})
    : _llm = _config.llm,
      _tts = _config.tts,
      _stt = _config.stt,
      _audioQueue = AudioQueue(
        sink: audioSink,
        audioFormat: _config.tts.audioFormat,
      ) {
    _history.add(
      ChatMessage(
        role: MessageRole.system,
        content: _composeSystemPrompt(_config),
      ),
    );
    _normalizer = SpeechTextNormalizer(stripAudioTags: !_tts.supportsAudioTags);
  }

  final VocraConfig _config;
  final MicSource _mic;
  final LlmProvider _llm;
  final TtsProvider _tts;
  final SttTransport _stt;
  final AudioQueue _audioQueue;
  final TurnMachine _turnMachine = TurnMachine();

  /// Strips markdown/emojis/(unsupported) audio tags from text before it is
  /// sent to TTS. Built from the TTS's [TtsProvider.supportsAudioTags].
  late final SpeechTextNormalizer _normalizer;

  final List<ChatMessage> _history = [];

  final StreamController<TranscriptEvent> _transcriptsController =
      StreamController<TranscriptEvent>.broadcast();
  final StreamController<List<TranscriptEvent>> _messagesController =
      StreamController<List<TranscriptEvent>>.broadcast();
  final StreamController<TurnMetrics> _metricsController =
      StreamController<TurnMetrics>.broadcast();
  final StreamController<VoiceError> _errorsController =
      StreamController<VoiceError>.broadcast();

  /// Collapses raw interim/final events into the running conversation view
  /// emitted on [messages].
  final TranscriptAggregator _aggregator = TranscriptAggregator();

  StreamSubscription<dynamic>? _micSub;
  StreamSubscription<TranscriptEvent>? _sttSub;
  StreamSubscription<void>? _drainedSub;
  StreamSubscription<int>? _clipStartedSub;

  bool _micForwardingEnabled = true;
  // True between startConversation() and stopConversation(): the mic + STT
  // are live. Typed turns (sendText) can also run while this is false, in
  // which case there's no mic to pause/resume and the engine rests at idle
  // rather than listening.
  bool _conversationActive = false;
  Cancellation? _turnCancel;
  Stopwatch? _turnStopwatch;
  TurnMetrics _currentMetrics = const TurnMetrics();
  StringBuffer? _assistantText;

  Stream<TurnState> get turnState => _turnMachine.stream;
  Stream<TranscriptEvent> get transcripts => _transcriptsController.stream;

  /// The aggregated conversation view: emits the full running list of
  /// user/assistant messages (interims collapsed in place — see
  /// [TranscriptAggregator]) on every change. Most UIs bind to this instead of
  /// the raw [transcripts] events. Broadcast, so new listeners see the next
  /// change; seed the initial list from [transcripts] or an empty list.
  Stream<List<TranscriptEvent>> get messages => _messagesController.stream;
  Stream<TurnMetrics> get metrics => _metricsController.stream;
  Stream<VoiceError> get errors => _errorsController.stream;

  /// The single funnel for every transcript event: emits the raw event on
  /// [transcripts] and the updated aggregated list on [messages].
  void _emitTranscript(TranscriptEvent event) {
    _transcriptsController.add(event);
    _messagesController.add(_aggregator.add(event));
  }

  bool get _isHalfDuplex => _config.duplex == DuplexMode.halfDuplex;

  /// Minimum interim-transcript length while [TurnState.speaking] that
  /// counts as the user barging in, for [DuplexMode.fullDuplex] (spec §9).
  /// Only meaningful with native echo cancellation enabled — without it,
  /// the mic would pick up the AI's own voice and this would fire
  /// immediately on every reply.
  int get _bargeInThreshold => switch (_config.sensitivity) {
    BargeInSensitivity.relaxed => 20,
    BargeInSensitivity.balanced => 12,
    BargeInSensitivity.eager => 6,
  };

  Future<void> startConversation() async {
    _conversationActive = true;
    // Establish the LLM/TTS network paths (DNS + TCP + TLS) while the mic and
    // STT transport spin up, so the first turn doesn't pay the handshake.
    unawaited(_warmUpProviders());
    // Mic capture and the STT transport are independent; starting them
    // concurrently overlaps the STT socket connect with recorder startup.
    await Future.wait([_mic.start(), _stt.start()]);

    _micSub = _mic.pcm16.listen((frame) {
      if (_micForwardingEnabled) _stt.sendAudio(frame);
    });
    _sttSub = _stt.transcripts.listen(
      _onSttTranscript,
      // A dropped STT connection (e.g. Deepgram WS closed by the network)
      // surfaces as a stream error rather than silently going quiet (R4).
      onError: (Object error, StackTrace stackTrace) {
        if (error is VoiceError) _errorsController.add(error);
      },
    );

    _turnMachine.transitionTo(TurnState.listening);

    // If configured, the assistant speaks first. Fire-and-forget: start() must
    // return so VocraSession can mark itself started (otherwise stop() during
    // the greeting would be a no-op). The greeting runs as a normal turn from
    // `listening`, and must run AFTER mic.start() because a full-duplex mic
    // only resumes forwarding — it can't start capture — after the turn.
    final greeting = _config.greeting;
    if (greeting != null) unawaited(_beginGreeting(greeting));
  }

  /// Composes the system prompt seeded into history. With
  /// [VocraConfig.naturalSpeech] off (the default) the app's prompt is used
  /// verbatim; on, it's followed by a voice-conversation style guide, plus
  /// audio-tag guidance when the TTS renders tags.
  static String _composeSystemPrompt(VocraConfig config) {
    if (!config.naturalSpeech) return config.systemPrompt;
    final buffer = StringBuffer(config.systemPrompt)
      ..write('\n\n')
      ..write(_naturalSpeechPreamble);
    if (config.tts.supportsAudioTags) {
      buffer
        ..write(' ')
        ..write(_audioTagAddendum);
    }
    return buffer.toString();
  }

  static const String _naturalSpeechPreamble =
      'Voice style: you are speaking aloud in a live voice conversation, so '
      'reply like a person talking, not like a writer. Keep replies brief and '
      'conversational, usually one to three sentences unless the user asks for '
      'detail. Use contractions and everyday words. Natural interjections like '
      '"oh", "hmm", or "right" are fine in moderation, and light laughter is '
      'written as words such as "haha", never as a stage direction. Do not use '
      'markdown, bullet points, emojis, or any text formatting: everything you '
      'write is spoken. Say numbers, dates, and symbols the way you would say '
      'them out loud.';

  static const String _audioTagAddendum =
      'You may occasionally include a bracketed audio tag such as [laughs], '
      '[sighs], or [whispers] to color your delivery, at most one per reply and '
      'only where it genuinely fits.';

  /// Default prompt used by [Greeting.generated] when no instruction is given.
  static const String _defaultGreetingInstruction =
      'The conversation is just starting. Greet the user warmly in one or two '
      'short sentences and invite them to speak. Do not mention these '
      'instructions.';

  /// Runs the opening assistant turn for [greeting]. For [TextGreeting] the
  /// text is spoken verbatim (no LLM call); for [GeneratedGreeting] the LLM is
  /// asked to produce the opener via an ephemeral user instruction that is
  /// sent for this one call but never stored in history (the reply is stored).
  Future<void> _beginGreeting(Greeting greeting) {
    return switch (greeting) {
      TextGreeting(:final text) => _runAssistantTurn(
        (_) => Stream<String>.value(text),
      ),
      GeneratedGreeting(:final instruction) => _runAssistantTurn(
        (cancel) => _llm.streamCompletion(
          [
            ..._history,
            ChatMessage(
              role: MessageRole.user,
              content: instruction ?? _defaultGreetingInstruction,
            ),
          ],
          temperature: _config.temperature,
          maxTokens: _config.maxTokens,
          cancel: cancel,
        ),
      ),
    };
  }

  /// Speaks [text] in the assistant's voice as a scripted turn — no LLM call.
  /// The text is spoken through the normal TTS/playback pipeline, emitted on
  /// [transcripts], and appended to history as an assistant message. Dispatch
  /// semantics match [sendText]: a call while a turn is already in flight is
  /// dropped, and this future completes when the turn is dispatched, not when
  /// playback finishes.
  Future<void> speak(String text) async {
    unawaited(_runAssistantTurn((_) => Stream<String>.value(text)));
  }

  /// Best-effort pre-warm of the LLM and TTS network paths. Fire-and-forget:
  /// a failure here must never delay or crash conversation start, so every
  /// error is swallowed (providers also swallow internally — this is a second
  /// guard against a misbehaving third-party provider).
  Future<void> _warmUpProviders() async {
    try {
      await Future.wait([_llm.warmUp(), _tts.warmUp()]);
    } catch (_) {}
  }

  Future<void> stopConversation() async {
    _conversationActive = false;
    _turnCancel?.cancel();
    await _audioQueue.interrupt();
    await _cancelTurnSubs();

    await _micSub?.cancel();
    _micSub = null;
    await _sttSub?.cancel();
    _sttSub = null;

    // Best-effort teardown: a mic or STT transport that throws while
    // stopping (e.g. an audio device already in a bad state) must not leave
    // the engine stuck outside `idle`, or every later start attempt would
    // be silently refused and the session could never be revived.
    try {
      await _mic.stop();
    } catch (_) {}
    try {
      await _stt.stop();
    } catch (_) {}

    _turnMachine.transitionTo(TurnState.idle);
  }

  /// Typed input — skips STT and starts a turn directly. Like an STT final
  /// transcript, this dispatches the turn rather than waiting for the
  /// entire LLM/TTS/playback cycle to finish — callers track progress via
  /// [turnState]/[transcripts]/[metrics], not this future.
  Future<void> sendText(String text) async {
    // A spoken turn's user text reaches [transcripts] via STT; typed input
    // has no STT leg, so emit the equivalent final user event here — the
    // transcript stream is the full conversation record either way.
    _emitTranscript(
      TranscriptEvent(source: TranscriptSource.user, text: text, isFinal: true),
    );
    unawaited(_beginTurn(text));
  }

  /// User cut-in (full-duplex barge-in, or a manual "stop talking" call in
  /// half-duplex): cancels the in-flight LLM/TTS work and returns to
  /// listening without tearing the session down.
  Future<void> interrupt() async {
    if (_turnMachine.state == TurnState.idle) return;

    _turnCancel?.cancel();
    await _audioQueue.interrupt();
    await _cancelTurnSubs();

    if (_isHalfDuplex && _conversationActive) {
      _micForwardingEnabled = true;
      await _resumeMicSafely();
    }
    _returnToRest();
  }

  /// Restarts mic capture after a turn. Resume runs on fire-and-forget paths
  /// (turn drain, barge-in interrupt), so a throwing [MicSource.resume] must
  /// surface on [errors] — not escape as an unhandled async exception and
  /// crash the app. After a failed resume the session is listening but deaf;
  /// the app can recover with stop()/start().
  Future<void> _resumeMicSafely() async {
    try {
      await _mic.resume();
    } catch (e) {
      _errorsController.add(
        e is VoiceError
            ? e
            : ProviderError(
                provider: 'microphone',
                statusCode: null,
                message: 'Failed to restart microphone capture: $e',
              ),
      );
    }
  }

  Future<void> dispose() async {
    _turnCancel?.cancel();
    await _cancelTurnSubs();
    await _micSub?.cancel();
    await _sttSub?.cancel();
    await _audioQueue.dispose();
    await _turnMachine.dispose();
    await _transcriptsController.close();
    await _messagesController.close();
    await _metricsController.close();
    await _errorsController.close();
  }

  void _onSttTranscript(TranscriptEvent event) {
    _emitTranscript(event);

    // Full-duplex barge-in (spec §9): the mic was never paused, so real
    // speech arriving while the AI is talking means the user cut in.
    // interrupt() alone is enough — it returns to listening, and the
    // utterance the user already started continues normally from there
    // once STT produces a final transcript for it.
    if (!_isHalfDuplex && _turnMachine.state == TurnState.speaking) {
      if (event.text.trim().length >= _bargeInThreshold) {
        unawaited(interrupt());
      }
      return;
    }

    if (!event.isFinal) return;
    if (event.text.trim().isEmpty) return;
    if (_turnMachine.state != TurnState.listening) return;
    unawaited(_beginTurn(event.text));
  }

  /// True while a turn is already being processed. A new turn must never
  /// overlap one in flight (`thinking`/`speaking`) — it would corrupt the
  /// shared per-turn state (stopwatch, metrics, assistant buffer, subs).
  bool get _turnInFlight =>
      _turnMachine.state == TurnState.thinking ||
      _turnMachine.state == TurnState.speaking;

  /// A turn started by user input (spoken via STT, or typed via [sendText]).
  /// Appends the user message, then runs the assistant turn against the LLM.
  Future<void> _beginTurn(String userText) async {
    // Guard before appending, so a dropped overlapping turn doesn't leave a
    // dangling user message with no reply.
    if (_turnInFlight) return;
    _addToHistory(ChatMessage(role: MessageRole.user, content: userText));
    await _runAssistantTurn(
      (cancel) => _llm.streamCompletion(
        _history,
        temperature: _config.temperature,
        maxTokens: _config.maxTokens,
        cancel: cancel,
      ),
    );
  }

  /// Runs one assistant turn: drives [tokenSource] (the LLM stream for a normal
  /// reply, or a scripted single-value stream for a greeting/[speak]) through
  /// sentence splitting → TTS → ordered playback, emitting interim/final
  /// transcripts and metrics. Shared by [_beginTurn], greetings, and [speak].
  ///
  /// The token source is a function of the turn's [Cancellation] so it can only
  /// begin producing once the turn scaffolding (cancel token, audio queue
  /// epoch) exists.
  Future<void> _runAssistantTurn(
    Stream<String> Function(Cancellation cancel) tokenSource,
  ) async {
    if (_turnInFlight) return;

    // Half-duplex pauses the mic during a turn — but only when there's a
    // live mic conversation to pause (R7). Typed-only turns skip this.
    //
    // Gate forwarding AND move to `thinking` synchronously, *before* the
    // `await _mic.pause()` below yields the event loop. If we awaited first,
    // a second STT final arriving during that yield would still observe
    // `listening`, slip past the overlap guard above, and start a second
    // concurrent turn — corrupting the shared per-turn state. Pausing the mic
    // just after the transition is safe: `_micForwardingEnabled` already
    // stops frames reaching STT the moment it's cleared.
    final pauseMic = _isHalfDuplex && _conversationActive;
    if (pauseMic) _micForwardingEnabled = false;
    _turnMachine.transitionTo(TurnState.thinking);
    if (pauseMic) await _mic.pause();

    final stopwatch = Stopwatch()..start();
    _turnStopwatch = stopwatch;
    _currentMetrics = const TurnMetrics();
    final assistantText = StringBuffer();
    _assistantText = assistantText;

    final cancel = Cancellation();
    _turnCancel = cancel;

    _audioQueue.beginTurn();
    final epoch = _audioQueue.epoch;

    var startedSpeaking = false;
    _clipStartedSub = _audioQueue.clipStarted.listen((_) {
      if (startedSpeaking) return;
      startedSpeaking = true;
      _currentMetrics = _currentMetrics.copyWith(
        timeToFirstVoice: stopwatch.elapsed,
      );
      _turnMachine.transitionTo(TurnState.speaking);
    });

    final drainedSub = _audioQueue.drained.listen((_) {
      _onTurnDrained(epoch);
    });
    _drainedSub = drainedSub;

    final splitter = SentenceSplitter();
    var sentenceIndex = 0;
    var gotFirstToken = false;

    // Normalizes a sentence for TTS and submits it — but only if anything
    // speakable remains. A sentence that normalizes to nothing (e.g. only an
    // emoji or a stripped tag) must NOT consume an AudioQueue index, or the
    // strictly-increasing index contract would leave a permanent gap and the
    // queue would stall waiting for a clip that never comes.
    void submitSpeakable(String sentence) {
      final speakable = _normalizer.normalize(sentence);
      if (speakable.isEmpty) return;
      _submitSentence(speakable, sentenceIndex++, epoch, cancel, stopwatch);
    }

    try {
      await for (final token in tokenSource(cancel)) {
        if (!gotFirstToken) {
          gotFirstToken = true;
          _currentMetrics = _currentMetrics.copyWith(ttft: stopwatch.elapsed);
        }
        assistantText.write(token);

        // Stream the assistant's text as it arrives (interim transcript,
        // cumulative) so UIs can render the reply word-by-word while it is
        // being spoken, mirroring user-side interims. The final event with
        // the complete text still fires when the turn drains. Transcripts keep
        // the ORIGINAL text; only the TTS input is normalized.
        _emitTranscript(
          TranscriptEvent(
            source: TranscriptSource.assistant,
            text: assistantText.toString(),
            isFinal: false,
          ),
        );

        // Eager-split only while still waiting on the very first sentence,
        // to get the first TTS clip out as early as possible (lower TTFV).
        for (final sentence in splitter.add(token, eager: sentenceIndex == 0)) {
          submitSpeakable(sentence);
        }
      }

      if (cancel.isCancelled) return; // interrupted — cleanup already done

      final remaining = splitter.flush();
      if (remaining != null) submitSpeakable(remaining);

      _audioQueue.completeTurn();
    } on VoiceError catch (e) {
      _errorsController.add(e);
      await _audioQueue.interrupt();
      await _cancelTurnSubs();
      if (_isHalfDuplex && _conversationActive) {
        _micForwardingEnabled = true;
        await _resumeMicSafely();
      }
      _returnToRest();
    }
  }

  void _submitSentence(
    String sentence,
    int index,
    int epoch,
    Cancellation cancel,
    Stopwatch stopwatch,
  ) {
    if (_currentMetrics.firstSentenceReady == null) {
      _currentMetrics = _currentMetrics.copyWith(
        firstSentenceReady: stopwatch.elapsed,
      );
    }

    final future = _tts.synthesize(sentence, cancel: cancel).then((bytes) {
      if (_currentMetrics.firstTtsReady == null) {
        _currentMetrics = _currentMetrics.copyWith(
          firstTtsReady: stopwatch.elapsed,
        );
      }
      return bytes;
    });
    // Surface synthesis failures on the errors stream; AudioQueue.submit
    // independently swallows the same error so a failed clip just never
    // arrives instead of crashing (see audio_queue.dart).
    unawaited(
      future.then(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (error is VoiceError) _errorsController.add(error);
        },
      ),
    );
    _audioQueue.submit(index, future, epoch);
  }

  void _onTurnDrained(int epoch) {
    if (epoch != _audioQueue.epoch) return; // stale — superseded by interrupt
    _turnStopwatch?.stop();
    _currentMetrics = _currentMetrics.copyWith(total: _turnStopwatch?.elapsed);
    _metricsController.add(_currentMetrics);

    final text = _assistantText?.toString() ?? '';
    if (text.isNotEmpty) {
      _addToHistory(ChatMessage(role: MessageRole.assistant, content: text));
      _emitTranscript(
        TranscriptEvent(
          source: TranscriptSource.assistant,
          text: text,
          isFinal: true,
        ),
      );
    }

    unawaited(_cancelTurnSubs());
    if (_isHalfDuplex && _conversationActive) {
      _micForwardingEnabled = true;
      unawaited(() async {
        // Release the platform audio output BEFORE restarting capture, so
        // recording never reopens while the player still holds the output
        // device — mirrors the ordering interrupt() already guarantees.
        try {
          await _audioQueue.releaseSink();
        } catch (_) {}
        await _resumeMicSafely();
      }());
    }
    _returnToRest();
  }

  /// Settles back to the resting state after a turn: [TurnState.listening]
  /// when a mic conversation is active, otherwise [TurnState.idle] (a
  /// typed-only turn). Respects [TurnMachine]'s legal-transition table: a
  /// turn that produced no audio is still in [TurnState.thinking] here, and
  /// thinking can't jump straight to listening — so it passes through
  /// speaking first (matching what a zero-length clip would have done),
  /// whereas thinking→idle is legal directly.
  void _returnToRest() {
    final target = _conversationActive ? TurnState.listening : TurnState.idle;
    if (_turnMachine.state == target) return;
    if (_turnMachine.state == TurnState.thinking &&
        target == TurnState.listening) {
      _turnMachine.transitionTo(TurnState.speaking);
    }
    _turnMachine.transitionTo(target);
  }

  Future<void> _cancelTurnSubs() async {
    await _drainedSub?.cancel();
    _drainedSub = null;
    await _clipStartedSub?.cancel();
    _clipStartedSub = null;
  }

  void _addToHistory(ChatMessage message) {
    _history.add(message);
    _trimHistory();
  }

  /// Keeps the system prompt (always `_history[0]`) and trims the oldest
  /// non-system messages once history exceeds [VocraConfig.maxHistoryMessages].
  void _trimHistory() {
    final overflow = _history.length - _config.maxHistoryMessages;
    if (overflow <= 0) return;
    _history.removeRange(1, 1 + overflow);
  }
}
