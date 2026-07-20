/// How (and whether) the assistant speaks first when a conversation starts.
///
/// A null [VocraConfig.greeting] (the default) keeps the current behavior: the
/// session opens in `listening` and the user speaks first. Set a [Greeting] to
/// have the assistant open the conversation instead.
sealed class Greeting {
  const Greeting();

  /// Speaks [text] verbatim as the assistant's opening turn — no LLM call, so
  /// it's instant and deterministic. The text flows through the normal
  /// TTS/playback pipeline and is recorded on [transcripts] and in history like
  /// any reply.
  const factory Greeting.text(String text) = TextGreeting;

  /// Asks the LLM to generate the opening line. [instruction] overrides the
  /// default prompt used to elicit the greeting; it is sent to the LLM for this
  /// one call but is **never stored** in conversation history. The generated
  /// greeting itself is stored, like any assistant reply.
  ///
  /// This adds one LLM round-trip of latency at session start; use
  /// [Greeting.text] when you want the opening to be instant.
  const factory Greeting.generated({String? instruction}) = GeneratedGreeting;

  /// Explicitly no greeting: the session opens in `listening` and the user
  /// speaks first. Identical to leaving [VocraConfig.greeting] null; exists so a
  /// conditional reads cleanly without a nullable dance, e.g.
  /// `greeting: returning ? Greeting.text('Welcome back!') : const Greeting.none()`.
  const factory Greeting.none() = NoGreeting;
}

/// A fixed, LLM-free opening line. See [Greeting.text].
class TextGreeting extends Greeting {
  const TextGreeting(this.text);

  final String text;
}

/// An LLM-generated opening line. See [Greeting.generated].
class GeneratedGreeting extends Greeting {
  const GeneratedGreeting({this.instruction});

  /// Optional override for the prompt that elicits the greeting. When null, a
  /// sensible default instruction is used.
  final String? instruction;
}

/// An explicit "no greeting" sentinel. See [Greeting.none].
class NoGreeting extends Greeting {
  const NoGreeting();
}
