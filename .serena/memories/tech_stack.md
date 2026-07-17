- Dart SDK `^3.12.0`, Flutter `>=3.44.0`. Dart-native pub workspaces (root `pubspec.yaml`
  `workspace:` list) + melos `^8.0.0` on top for scripts.
- `vocra_core`: pure Dart, deps `dio` (HTTP), `web_socket_channel` (WS). Dev deps: `test`,
  `mocktail`, `lints`.
- `vocra_flutter`: Flutter plugin, deps `vocra_core` (path dep), `just_audio`, `record`,
  `audio_session`. Has native platform code: `ios/Classes/*.swift`, Android
  `android/src/main/...kotlin` for `NativeAecMicSource` (full-duplex echo cancellation).
- iOS uses CocoaPods (not Swift Package Manager) — intentional, see `mem:core` ->
  ARCHITECTURE.md rationale.
- `packages/vocra_flutter/example/` is a runnable Flutter demo app + manual test harness
  (`key_entry_screen.dart` lets testers plug in their own Groq/Deepgram keys).