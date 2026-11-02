/// Helpers for testing games built on engine_core, without Flutter and
/// without depending on a test framework. Import it from tests only
/// (`package:engine_core/engine_core_testing.dart`); it uses `dart:io` for
/// golden files, so it is not part of the main library.
library;

export 'src/testing/game_tester.dart';
export 'src/testing/golden.dart';
