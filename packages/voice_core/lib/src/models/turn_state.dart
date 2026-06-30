/// The conversation's current phase (spec §4, §6.3).
///
/// Legal transitions are enforced by [TurnMachine], not by this enum itself:
/// idle→listening, listening→thinking, thinking→speaking, speaking→listening
/// or idle, and any state→idle on stop.
enum TurnState { idle, listening, thinking, speaking }
