import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:path/path.dart' as p;

import '../textures/atlas_catalog.dart';

/// Names a designer can refer to in this project, found by scanning it rather than
/// typed in: the classes the game defines, its atlas ids, the entity names in its
/// levels, and the engine's component names. Autocomplete offers from these.
class ProjectSymbols {
  final Set<String> classes;
  final Set<String> atlasIds;
  final Set<String> entityNames;
  final Set<String> components;

  const ProjectSymbols({
    required this.classes,
    required this.atlasIds,
    required this.entityNames,
    required this.components,
  });

  static final _classPattern = RegExp(
    r'^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+)*class\s+(\w+)',
    multiLine: true,
  );

  /// Scans [projectRoot]. Missing folders contribute nothing rather than failing, so
  /// a half-built project still gets completions.
  factory ProjectSymbols.scan(String projectRoot) {
    final classes = <String>{};
    final lib = Directory(p.join(projectRoot, 'lib'));
    if (lib.existsSync()) {
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final match in _classPattern.allMatches(file.readAsStringSync())) {
          classes.add(match.group(1)!);
        }
      }
    }

    final entityNames = <String>{};
    final levels = Directory(p.join(projectRoot, 'assets', 'levels'));
    if (levels.existsSync()) {
      for (final file in levels.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        try {
          final doc = LevelDocument.fromJson(
            (jsonDecode(file.readAsStringSync()) as Map)
                .cast<String, dynamic>(),
          );
          for (final entity in doc.entities) {
            if (entity.name != null) entityNames.add(entity.name!);
          }
        } on Object {
          continue;
        }
      }
    }

    return ProjectSymbols(
      classes: classes,
      atlasIds: AtlasCatalog.read(projectRoot).entries.keys.toSet(),
      entityNames: entityNames,
      components: allComponentSchemas.keys.toSet(),
    );
  }

  /// Every known name, sorted, with its kind, for completion lists.
  List<(String name, String kind)> get all => [
    for (final name in classes) (name, 'class'),
    for (final name in atlasIds) (name, 'atlas'),
    for (final name in entityNames) (name, 'entity'),
    for (final name in components) (name, 'component'),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  /// The names that start with [prefix] (case-sensitive, as Dart is), without
  /// repeating a name that appears under two kinds. An empty prefix offers nothing,
  /// so completion only appears once the designer has typed something.
  List<(String name, String kind)> completionsFor(String prefix) {
    if (prefix.isEmpty) return const [];
    final seen = <String>{};
    return [
      for (final item in all)
        if (item.$1.startsWith(prefix) && seen.add(item.$1)) item,
    ];
  }
}
