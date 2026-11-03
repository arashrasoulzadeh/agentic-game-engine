/// Returns the process's current resident memory in bytes, or `null`
/// where that isn't available (web — Dart has no memory-usage API
/// there). Picked at compile time via `dart.library.io`'s presence, the
/// standard conditional-export idiom for a platform capability that
/// only exists on some targets, so this package still compiles for web
/// (`dart:io` isn't available there at all).
export 'debug_memory_stub.dart' if (dart.library.io) 'debug_memory_io.dart';
