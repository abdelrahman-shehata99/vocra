import 'dart:async';

import 'package:flutter/material.dart';
import 'package:voice_flutter/voice_flutter.dart';

/// Conversation screen (spec §10): mic toggle, live transcript, turn-state
/// indicator, latency readout, and a clear-conversation button.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.config});

  final VoiceConfig config;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late VoiceSession _session;

  TurnState _turnState = TurnState.idle;
  final List<TranscriptEvent> _transcript = [];
  TurnMetrics? _lastMetrics;
  String? _lastError;
  bool _starting = false;

  StreamSubscription<TurnState>? _turnStateSub;
  StreamSubscription<TranscriptEvent>? _transcriptsSub;
  StreamSubscription<TurnMetrics>? _metricsSub;
  StreamSubscription<VoiceError>? _errorsSub;

  bool get _isActive => _turnState != TurnState.idle;

  @override
  void initState() {
    super.initState();
    _session = VoiceSession(config: widget.config);
    _wire(_session);
  }

  void _wire(VoiceSession session) {
    _turnStateSub = session.turnState.listen((s) {
      if (!mounted) return;
      setState(() => _turnState = s);
    });
    _transcriptsSub = session.transcripts.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event.isFinal) {
          _transcript.add(event);
        } else {
          // Replace the trailing interim event from the same speaker
          // in-place instead of growing the list per partial update.
          if (_transcript.isNotEmpty &&
              !_transcript.last.isFinal &&
              _transcript.last.source == event.source) {
            _transcript[_transcript.length - 1] = event;
          } else {
            _transcript.add(event);
          }
        }
      });
    });
    _metricsSub = session.metrics.listen((m) {
      if (!mounted) return;
      setState(() => _lastMetrics = m);
    });
    _errorsSub = session.errors.listen((e) {
      if (!mounted) return;
      setState(() => _lastError = e.message);
    });
  }

  Future<void> _toggleMic() async {
    if (_isActive) {
      await _session.stop();
      return;
    }
    setState(() => _starting = true);
    await _session.requestPermissions();
    await _session.start();
    if (!mounted) return;
    setState(() => _starting = false);
  }

  Future<void> _clearConversation() async {
    final oldSession = _session;
    await _turnStateSub?.cancel();
    await _transcriptsSub?.cancel();
    await _metricsSub?.cancel();
    await _errorsSub?.cancel();

    final freshSession = VoiceSession(config: widget.config);
    setState(() {
      _session = freshSession;
      _transcript.clear();
      _lastMetrics = null;
      _lastError = null;
      _turnState = TurnState.idle;
    });
    _wire(freshSession);

    await oldSession.dispose();
  }

  @override
  void dispose() {
    _turnStateSub?.cancel();
    _transcriptsSub?.cancel();
    _metricsSub?.cancel();
    _errorsSub?.cancel();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearConversation,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TurnStateBanner(state: _turnState),
            if (_lastError != null)
              Container(
                width: double.infinity,
                color: Colors.red.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _lastError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.red,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _lastError = null),
                    ),
                  ],
                ),
              ),
            if (_lastMetrics != null) _MetricsRow(metrics: _lastMetrics!),
            Expanded(
              child: _transcript.isEmpty
                  ? const Center(child: Text('Tap the mic to start talking.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _transcript.length,
                      itemBuilder: (context, index) {
                        final event = _transcript[index];
                        final isUser = event.source == TranscriptSource.user;
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              event.text.isEmpty ? '…' : event.text,
                              style: TextStyle(
                                fontStyle: event.isFinal
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _starting ? null : _toggleMic,
        backgroundColor: _isActive ? Colors.red : null,
        child: _starting
            ? const CircularProgressIndicator()
            : Icon(_isActive ? Icons.stop : Icons.mic),
      ),
    );
  }
}

class _TurnStateBanner extends StatelessWidget {
  const _TurnStateBanner({required this.state});

  final TurnState state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      TurnState.idle => ('Idle', Colors.grey, Icons.power_settings_new),
      TurnState.listening => ('Listening…', Colors.blue, Icons.hearing),
      TurnState.thinking => ('Thinking…', Colors.orange, Icons.psychology),
      TurnState.speaking => ('Speaking…', Colors.green, Icons.volume_up),
    };
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics});

  final TurnMetrics metrics;

  @override
  Widget build(BuildContext context) {
    String fmt(Duration? d) => d == null ? '—' : '${d.inMilliseconds}ms';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 12,
        children: [
          Text(
            'ttft: ${fmt(metrics.ttft)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'firstVoice: ${fmt(metrics.timeToFirstVoice)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'total: ${fmt(metrics.total)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
