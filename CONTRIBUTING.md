# Contributing to Vocra

Thanks for your interest in improving Vocra! This is a melos + Dart pub
workspace monorepo with two published packages:

- `packages/vocra_core` — pure-Dart engine, provider adapters, transport
  (**no Flutter dependency**).
- `packages/vocra_flutter` — Flutter platform layer (mic, playback,
  permissions, `VocraSession`).

## Setup

Requires the Flutter SDK (3.44.x or newer; Dart 3.12+).

```sh
dart pub get            # resolve the whole workspace
dart run melos bootstrap
```

## Everyday commands

| Command | Purpose |
|---|---|
| `dart run melos run analyze` | `dart analyze` across all packages |
| `dart run melos run format` | check formatting (no auto-fix) |
| `dart run melos run test` | `dart test` (vocra_core) + `flutter test` (vocra) |
| `cd packages/vocra_core && dart test` | faster iteration on the engine |

Run `dart run melos run analyze` and `dart run melos run test` before opening a
PR. Format with `dart format .`.

## Conventions

- Keep `vocra_core` free of `package:flutter` imports — Flutter-specific code
  belongs in `vocra_flutter`, wired through the `AudioSink` / `MicSource` /
  `KeyStore` interfaces.
- `TurnMachine` is the sole owner of turn-state transitions; only `VoiceEngine`
  drives it.
- Map provider failures to a typed `VoiceError` subtype — never let a raw
  exception cross a provider/engine boundary.
- Non-obvious behavioral decisions get a dedicated, descriptively-named test.
- Commit messages: present tense, one logical change per commit.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design rationale
behind the non-obvious parts (turn-state, `AudioQueue`, Deepgram final-mapping,
greeting, full-duplex AEC) before changing them.

## Releasing

Both packages version in lockstep. Publish `vocra_core` first, then
`vocra_flutter` (see the release runbook in the repo README).
