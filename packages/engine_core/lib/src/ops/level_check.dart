import 'dart:convert';

import 'package:engine_schema/engine_schema.dart';

import '../content/level.dart';
import '../content/level_document.dart';
import '../validation/level_validator.dart';

/// The result of checking one level file's text: how many entities, the schema errors and warnings, or a
/// [fatal] reason it could not even be loaded. One implementation shared by `project.validate`, `level.validate`
/// and the safety pipeline, so they never disagree.
class LevelCheck {
  const LevelCheck({
    this.entities,
    this.errors = const [],
    this.warnings = const [],
    this.fatal,
  });

  final int? entities;
  final List<String> errors;
  final List<String> warnings;
  final String? fatal;

  bool get ok => fatal == null && errors.isEmpty;

  Map<String, Object?> toJson() => {
    'ok': ok,
    if (entities != null) 'entities': entities,
    'errors': [if (fatal != null) fatal, ...errors],
    'warnings': warnings,
  };
}

LevelCheck checkLevelText(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    return LevelCheck(fatal: 'not valid JSON (${e.message})');
  }
  if (json is! Map<String, dynamic>)
    return const LevelCheck(fatal: 'the level must be a JSON object');
  final LevelDocument doc;
  try {
    doc = LevelDocument.fromJson(json);
  } on LevelLoadException catch (e) {
    return LevelCheck(fatal: e.message);
  } on Object catch (e) {
    return LevelCheck(fatal: 'not a loadable level ($e)');
  }
  final issues = LevelValidator.forSchemas(allComponentSchemas).validate(doc);
  return LevelCheck(
    entities: doc.entities.length,
    errors: [
      for (final i in issues)
        if (i.severity == IssueSeverity.error) i.toString(),
    ],
    warnings: [
      for (final i in issues)
        if (i.severity != IssueSeverity.error) i.toString(),
    ],
  );
}
