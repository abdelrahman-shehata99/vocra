- Typed errors: all provider/engine failures surface as a `VoiceError` subtype (`AuthError`,
  `RateLimitError`, `NetworkError`, `ProviderError`, `ConfigError` — see
  `packages/vocra_core/lib/src/models/voice_error.dart`), including mid-stream failures
  (dropped SSE/WebSocket connections). Never let a raw provider exception leak out of an
  adapter or the engine — map it to the closest `VoiceError` subtype.
- State machine discipline: `TurnMachine` (packages/vocra_core/lib/src/engine/turn_machine.dart)
  is the sole owner of turn-state transitions; only `VoiceEngine` drives it. Don't transition
  turn state from anywhere else, even for edge cases — see `mem:core` -> ARCHITECTURE.md for
  how the empty-reply edge case is handled without adding a new illegal transition.
  invariants documented in ARCHITECTURE.md when extending them.
- Re-entrancy guards (e.g. `VoiceSession.start`/`stop`) set their guard flag synchronously
  before the first `await`, specifically to close races from rapid double-calls (e.g.
  double-tapped UI button). Follow this pattern for any new start/stop-style guarded method.
- Tests: `test` package for vocra_core (mocktail for mocking, `stream_channel` /
  `fake_websocket_channel.dart` fakes for WS-based providers), `flutter_test` for vocra_flutter.
  Test files mirror `lib/src/...` structure under `test/...`. Non-obvious behavioral decisions
  get a dedicated named test (e.g. deepgram_stt_test.dart's "maps speech_final ... not raw
  is_final") rather than just being asserted incidentally — grep test descriptions before
  assuming a behavior is untested.