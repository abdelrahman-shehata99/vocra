# Architecture notes

This documents how the pieces in `voice_core` fit together, and a handful
of places where the implementation extends the literal build spec — always
with a concrete reason, never speculatively.

## Turn flow (half-duplex)

```
listening --[STT speech_final]--> thinking --[first audio clip plays]--> speaking --[audio queue drains]--> listening
   ^                                                                                                              |
   +--------------------------------------------------------------------------------------------------------------+
```

`TurnMachine` only allows the legal transitions above (plus any state →
`idle` on stop). `VoiceEngine` drives it; nothing else is allowed to
transition it directly, which is what makes the "mic must not reach STT
while speaking" invariant (R7) enforceable in one place.

## Why `AudioQueue` has `completeTurn`/`drained`/`clipStarted`

The spec's documented `AudioQueue` contract is:

```dart
int get epoch;
void beginTurn();
void submit(int index, Future<Uint8List> clip, int epoch);
Future<void> interrupt();
```

That's enough to describe *ordering* (out-of-order TTS resolution still
plays in order) and *interruption* (stale-epoch clips dropped), but the
engine also needs to know two things the literal contract has no way to
express:

1. **"The turn is over and nothing more is coming."** Sentences arrive
   incrementally as the LLM streams, so neither the engine nor the queue
   knows the total clip count in advance. `completeTurn()` is the engine's
   signal, sent once the LLM stream ends and the sentence splitter is
   flushed; `drained` fires once everything submitted before that point has
   finished playing. This is what lets the engine know when to resume the
   mic and emit the `total` metric.
2. **"Audio has actually started playing"** — distinct from "bytes are
   ready" (`firstTtsReady`). Playback order means clip 0 must finish before
   clip 1 plays even if clip 1's TTS resolved first, so "first clip ready"
   and "first clip audible" can differ. `clipStarted` fires exactly when a
   clip is handed to `AudioSink.enqueue`, which is what the engine uses to
   transition into `TurnState.speaking` and record `timeToFirstVoice`.

Both are additive — the documented members behave exactly as specified.

## Why `DeepgramStt` maps `speech_final`, not `is_final`, to `TranscriptEvent.isFinal`

Deepgram's streaming API has two different "final" signals:

- `is_final` — this segment's wording is locked in, but the speaker may
  still be talking (fires multiple times per utterance).
- `speech_final` — endpointing detected the speaker stopped (fires once,
  at the end of an utterance).

The build spec's prose is slightly ambiguous here: §7.2 says "Emit
`TranscriptEvent(user, text, isFinal: is_final)`", but §6.4 step 2 says the
engine should start the LLM turn "On STT final transcript (utterance end /
`speech_final`)". Wiring `isFinal` to the lower-level `is_final` would fire
the LLM mid-utterance, possibly several times per turn — wiring it to
`speech_final` (what this implementation does) makes `isFinal` mean
exactly what `VoiceEngine` needs it to mean: "the user is done talking,
start the turn." This is covered by a dedicated test
(`deepgram_stt_test.dart`: *"maps speech_final ... not raw is_final"*).

## Why `_returnToListening()` passes through `speaking` for empty replies

`TurnMachine`'s legal transitions are `thinking → speaking` or
`thinking → idle` — there's no `thinking → listening`. An LLM reply that
produces zero playable sentences (an edge case, but a real one) would
otherwise need to skip straight from `thinking` back to `listening`, which
is illegal. `VoiceEngine._returnToListening()` passes through `speaking`
for a single (instant) transition in that case, which is exactly the state
sequence that *would* have happened had there been a zero-duration clip —
it doesn't bend the state machine's invariants, just accounts for the
zero-clip edge case consistently.

## Error typing is end-to-end, including mid-stream failures

Every adapter (`GroqLlm`, `DeepgramTts`, `DeepgramStt`) maps provider
failures to a typed `VoiceError` subtype (R4) — and this includes failures
that occur *after* a request has already started succeeding: a dropped
connection mid-SSE-stream from Groq, or a WebSocket that closes
unexpectedly mid-conversation from Deepgram, both surface as a typed
`NetworkError` rather than a raw exception leaking out of the engine. See
`groq_llm_test.dart`'s *"maps a connection drop mid-stream..."* test and
`deepgram_stt_test.dart`'s connection-error tests.

## `VoiceSession` re-entrancy

`VoiceSession.start()`/`stop()` each set a guard flag *synchronously*,
before their first `await`, specifically so that two rapid calls (e.g. a
double-tapped mic button, before the first call's permission/audio-session
setup has resolved) can't both slip past a "are we already started" check
and run concurrently.
