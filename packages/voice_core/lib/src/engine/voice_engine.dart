import 'dart:async';

import '../io/audio_sink.dart';
import '../io/mic_source.dart';
import '../models/chat_message.dart';
import '../models/transcript_event.dart';
import '../models/turn_metrics.dart';
import '../models/turn_state.dart';
import '../models/voice_config.dart';
import '../models/voice_error.dart';
import '../providers/llm_provider.dart';
import '../providers/stt_transport.dart';
import '../providers/tts_provider.dart';
import '../util/cancellation.dart';
import 'audio_queue.dart';
import 'sentence_splitter.dart';
import 'turn_machine.dart';

/// The pure-Dart orchestrator that wires STT, the LLM, TTS, and ordered
/// audio playback into one half-duplex conversation loop (spec §6.4).
class VoiceEngine {
  VoiceEngine(
    this._config, {
    required AudioSink audioSink,
    required MicSource mic,
  }) : _mic = mic,
       _llm = _config.llm,
       _tts = _config.tts,
       _stt = _config.stt,
       _audioQueue = AudioQueue(
         sink: audioSink,
         audioFormat: _config.tts.audioFormat,
       ) {
    _history.add(
      ChatMessage(role: MessageRole.system, content: _config.systemPrompt),
    );
  }

  final VoiceConfig _config;
  final MicSource _mic;
  final LlmProvider _llm;
  final TtsProvider _tts;
  final SttTransport _stt;
  final AudioQueue _audioQueue;
  final TurnMachine _turnMachine = TurnMachine();

  final List<ChatMessage> _history = [];

  final StreamController<TranscriptEvent> _transcriptsController =
      StreamController<TranscriptEvent>.broadcast();
  final StreamController<TurnMetrics> _metricsController =
      StreamController<TurnMetrics>.broadcast();
  final StreamController<VoiceError> _errorsController =
      StreamController<VoiceError>.broadcast();

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
  Stream<TurnMetrics> get metrics => _metricsController.stream;
  Stream<VoiceError> get errors => _errorsController.stream;

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
    await _mic.start();
    await _stt.start();

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

    await _mic.stop();
    await _stt.stop();

    _turnMachine.transitionTo(TurnState.idle);
  }

  /// Typed input — skips STT and starts a turn directly. Like an STT final
  /// transcript, this dispatches the turn rather than waiting for the
  /// entire LLM/TTS/playback cycle to finish — callers track progress via
  /// [turnState]/[transcripts]/[metrics], not this future.
  Future<void> sendText(String text) async {
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
      await _mic.resume();
    }
    _returnToRest();
  }

  Future<void> dispose() async {
    _turnCancel?.cancel();
    await _cancelTurnSubs();
    await _micSub?.cancel();
    await _sttSub?.cancel();
    await _audioQueue.dispose();
    await _turnMachine.dispose();
    await _transcriptsController.close();
    await _metricsController.close();
    await _errorsController.close();
  }

  void _onSttTranscript(TranscriptEvent event) {
    _transcriptsController.add(event);

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

  Future<void> _beginTurn(String userText) async {
    // A turn may begin from `listening` (the user spoke, mic conversation
    // active) or from `idle` (typed input via sendText with no mic). It must
    // never overlap an in-flight turn (`thinking`/`speaking`).
    if (_turnMachine.state == TurnState.thinking ||
        _turnMachine.state == TurnState.speaking) {
      return;
    }

    _addToHistory(ChatMessage(role: MessageRole.user, content: userText));

    // Half-duplex pauses the mic during a turn — but only when there's a
    // live mic conversation to pause (R7). Typed-only turns skip this.
    if (_isHalfDuplex && _conversationActive) {
      _micForwardingEnabled = false;
      await _mic.pause();
    }
    _turnMachine.transitionTo(TurnState.thinking);

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

    try {
      await for (final token in _llm.streamCompletion(
        _history,
        temperature: _config.temperature,
        maxTokens: _config.maxTokens,
        cancel: cancel,
      )) {
        if (!gotFirstToken) {
          gotFirstToken = true;
          _currentMetrics = _currentMetrics.copyWith(ttft: stopwatch.elapsed);
        }
        assistantText.write(token);

        // Eager-split only while still waiting on the very first sentence,
        // to get the first TTS clip out as early as possible (lower TTFV).
        for (final sentence in splitter.add(token, eager: sentenceIndex == 0)) {
          _submitSentence(sentence, sentenceIndex++, epoch, cancel, stopwatch);
        }
      }

      if (cancel.isCancelled) return; // interrupted — cleanup already done

      final remaining = splitter.flush();
      if (remaining != null) {
        _submitSentence(remaining, sentenceIndex++, epoch, cancel, stopwatch);
      }

      _audioQueue.completeTurn();
    } on VoiceError catch (e) {
      _errorsController.add(e);
      await _audioQueue.interrupt();
      await _cancelTurnSubs();
      if (_isHalfDuplex && _conversationActive) {
        _micForwardingEnabled = true;
        await _mic.resume();
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
      _transcriptsController.add(
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
      unawaited(_mic.resume());
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
  /// non-system messages once history exceeds [VoiceConfig.maxHistoryMessages].
  void _trimHistory() {
    final overflow = _history.length - _config.maxHistoryMessages;
    if (overflow <= 0) return;
    _history.removeRange(1, 1 + overflow);
  }
}
