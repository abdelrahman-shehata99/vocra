Before considering a coding task done, from repo root:
1. `melos run analyze` — must be clean (`dart analyze .` across all packages).
2. `melos run format` — must be clean (`--set-exit-if-changed`, so format locally with
   `dart format .` in the affected package first if this fails).
3. `melos run test` — `dart test` (voice_core) + `flutter test` (voice_flutter) must pass.
If only one package was touched, the package-scoped commands in `mem:suggested_commands` are
faster for iteration, but run the melos-wide commands before declaring the task complete since
voice_flutter depends on voice_core (a voice_core change can break voice_flutter tests).