import 'package:flutter/material.dart';
import 'package:voice_flutter/voice_flutter.dart';

import 'conversation_screen.dart';

/// Key-entry screen (spec §10): collects Groq + Deepgram keys, an optional
/// persona, persists keys via [SecureKeyStore], and offers a cheap
/// "Test keys" call against each provider before starting a conversation.
class KeyEntryScreen extends StatefulWidget {
  KeyEntryScreen({super.key, KeyStore? keyStore})
    : keyStore = keyStore ?? SecureKeyStore();

  /// Injectable so widget tests can supply an in-memory fake instead of
  /// touching the real secure-storage platform channel (which has no mock
  /// in the test environment and hangs rather than throwing).
  final KeyStore keyStore;

  @override
  State<KeyEntryScreen> createState() => _KeyEntryScreenState();
}

enum _KeyTestState { untested, testing, ok, failed }

class _KeyEntryScreenState extends State<KeyEntryScreen> {
  static const _groqKeyName = 'groq_api_key';
  static const _deepgramKeyName = 'deepgram_api_key';

  KeyStore get _keyStore => widget.keyStore;
  final _groqController = TextEditingController();
  final _deepgramController = TextEditingController();
  final _personaController = TextEditingController(
    text: 'You are a helpful, concise voice assistant.',
  );

  _KeyTestState _groqState = _KeyTestState.untested;
  _KeyTestState _deepgramState = _KeyTestState.untested;
  String? _groqError;
  String? _deepgramError;
  bool _loadingStoredKeys = true;

  @override
  void initState() {
    super.initState();
    _loadStoredKeys();
  }

  Future<void> _loadStoredKeys() async {
    String? groqKey;
    String? deepgramKey;
    try {
      groqKey = await _keyStore.read(_groqKeyName);
      deepgramKey = await _keyStore.read(_deepgramKeyName);
    } catch (_) {
      // Secure storage unavailable (e.g. platform not set up yet) — fall
      // back to empty fields rather than blocking the screen forever.
    }
    if (!mounted) return;
    setState(() {
      _groqController.text = groqKey ?? '';
      _deepgramController.text = deepgramKey ?? '';
      _loadingStoredKeys = false;
    });
  }

  Future<void> _testGroqKey() async {
    final key = _groqController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _groqState = _KeyTestState.testing;
      _groqError = null;
    });

    final llm = GroqLlm(apiKey: key);
    try {
      await llm
          .streamCompletion(
            const [ChatMessage(role: MessageRole.user, content: 'hi')],
            temperature: 0,
            maxTokens: 1,
            cancel: Cancellation(),
          )
          .first
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _groqState = _KeyTestState.ok);
    } on AuthError {
      if (!mounted) return;
      setState(() {
        _groqState = _KeyTestState.failed;
        _groqError = 'Invalid Groq API key.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _groqState = _KeyTestState.failed;
        _groqError = 'Could not reach Groq: $e';
      });
    }
  }

  Future<void> _testDeepgramKey() async {
    final key = _deepgramController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _deepgramState = _KeyTestState.testing;
      _deepgramError = null;
    });

    final tts = DeepgramTts(apiKey: key);
    try {
      await tts
          .synthesize('hi', cancel: Cancellation())
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _deepgramState = _KeyTestState.ok);
    } on AuthError {
      if (!mounted) return;
      setState(() {
        _deepgramState = _KeyTestState.failed;
        _deepgramError = 'Invalid Deepgram API key.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deepgramState = _KeyTestState.failed;
        _deepgramError = 'Could not reach Deepgram: $e';
      });
    }
  }

  Future<void> _start() async {
    final groqKey = _groqController.text.trim();
    final deepgramKey = _deepgramController.text.trim();
    if (groqKey.isEmpty || deepgramKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both a Groq and a Deepgram key.')),
      );
      return;
    }

    try {
      await _keyStore.write(_groqKeyName, groqKey);
      await _keyStore.write(_deepgramKeyName, deepgramKey);
    } catch (_) {
      // Failing to persist shouldn't block starting with the keys already
      // in memory — the user just has to re-enter them next launch.
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          config: VoiceConfig(
            llm: GroqLlm(apiKey: groqKey),
            tts: DeepgramTts(apiKey: deepgramKey),
            stt: DeepgramStt(apiKey: deepgramKey),
            systemPrompt: _personaController.text.trim().isEmpty
                ? 'You are a helpful assistant.'
                : _personaController.text.trim(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _groqController.dispose();
    _deepgramController.dispose();
    _personaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice AI SDK Demo')),
      body: _loadingStoredKeys
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _KeyField(
                    label: 'Groq API key',
                    controller: _groqController,
                    state: _groqState,
                    error: _groqError,
                    onTest: _testGroqKey,
                  ),
                  const SizedBox(height: 16),
                  _KeyField(
                    label: 'Deepgram API key',
                    controller: _deepgramController,
                    state: _deepgramState,
                    error: _deepgramError,
                    onTest: _testDeepgramKey,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _personaController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Persona / system prompt (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _start,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Start conversation'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _KeyField extends StatelessWidget {
  const _KeyField({
    required this.label,
    required this.controller,
    required this.state,
    required this.error,
    required this.onTest,
  });

  final String label;
  final TextEditingController controller;
  final _KeyTestState state;
  final String? error;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            switch (state) {
              _KeyTestState.testing => const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              _KeyTestState.ok => const Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
              _KeyTestState.failed => const Icon(
                Icons.error,
                color: Colors.red,
              ),
              _KeyTestState.untested => TextButton(
                onPressed: onTest,
                child: const Text('Test'),
              ),
            },
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}
