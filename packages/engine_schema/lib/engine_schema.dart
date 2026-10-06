/// Pure-Dart component schemas for the agentic game engine.
///
/// Holds the field lists (names, types, ranges, defaults) of every component the
/// engine registers. It depends on nothing else, so the CLI and the studio can
/// validate levels without importing Flutter.
library;

export 'src/field_schema.dart';
export 'src/core_schemas.dart';
export 'src/flutter_schemas.dart';
export 'src/platformer_schemas.dart';
export 'src/all_schemas.dart';
