Before considering a coding task done, from repo root:
1. `melos run analyze` — must be clean (`dart analyze .` across all packages).
2. `melos run format` — must be clean (`--set-exit-if-changed`, so format locally with
   `dart format .` in the affected package first if this fails).
3. `melos run test` — `dart test` (vocra_core) + `flutter test` (vocra) must pass.
If only one package was touched, the package-scoped commands in `mem:suggested_commands` are
faster for iteration, but run the melos-wide commands before declaring the task complete since
vocra depends on vocra_core (a vocra_core change can break vocra tests).