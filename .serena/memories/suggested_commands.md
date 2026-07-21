Run from repo root (`vocra/`) unless noted.

- `dart pub get` — resolve whole workspace (root command resolves all workspace packages at once).
- `melos bootstrap` — link local packages together (needed after clone or dependency changes).
- `melos run analyze` — `dart analyze .` across all packages.
- `melos run format` — `dart format --set-exit-if-changed .` across all packages (fails on
  unformatted code, doesn't auto-fix).
- `melos run test` — `dart test` for non-Flutter packages (vocra_core) + `flutter test` for
  Flutter packages (vocra), dispatched via melos `--dir-exists=test` filter.
- Package-scoped alternative: `cd packages/vocra_core && dart test` /
  `cd packages/vocra_flutter && flutter test` for faster iteration on one package.
- Example app: `cd packages/vocra_flutter/example && flutter run` (needs a connected
  device/simulator; Test-keys flow lets you supply Groq/Deepgram keys at runtime).
- `melos` itself must be globally activated once: `dart pub global activate melos`.