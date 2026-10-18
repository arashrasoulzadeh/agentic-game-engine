import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

/// Where a project keeps its brushes, relative to the project root.
const brushLibraryFile = 'assets/studio_brushes.json';

/// Loads and saves the project's [BrushLibrary]. A missing or unreadable file is an
/// empty library, never an error: brushes are a convenience and must not stop a level
/// opening.
class BrushStore {
  final String projectRoot;
  const BrushStore(this.projectRoot);

  File get _file => File(p.join(projectRoot, brushLibraryFile));

  BrushLibrary load() {
    try {
      return BrushLibrary.fromJson(
        jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>,
      );
    } on Object {
      return BrushLibrary();
    }
  }

  void save(BrushLibrary library) {
    _file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(library.toJson()),
      );
  }
}

/// Loads and saves prefabs as `prefabs/<name>.json`.
class PrefabStore {
  final String projectRoot;
  const PrefabStore(this.projectRoot);

  static final _validName = RegExp(r'^[A-Za-z0-9_\-]+$');

  /// Whether [name] can be a prefab file name (letters, digits, `_`, `-`).
  static bool isValidName(String name) => _validName.hasMatch(name);

  String pathFor(String name) => p.join('prefabs', '$name.json');

  /// Writes [prefab] (overwriting a prefab of the same name) and returns its
  /// project-relative path. Throws [ArgumentError] for an unusable name.
  String save(Prefab prefab) {
    if (!isValidName(prefab.name)) {
      throw ArgumentError.value(
        prefab.name,
        'name',
        'use letters, digits, "_" and "-"',
      );
    }
    File(p.join(projectRoot, pathFor(prefab.name)))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(prefab.toJson()),
      );
    return pathFor(prefab.name);
  }

  /// The prefab at a project-relative [path], or null if missing or unreadable.
  Prefab? load(String path) {
    try {
      return Prefab.fromJson(
        jsonDecode(File(p.join(projectRoot, path)).readAsStringSync())
            as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  /// Project-relative paths of every saved prefab, sorted.
  List<String> list() {
    final dir = Directory(p.join(projectRoot, 'prefabs'));
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.json')) p.relative(f.path, from: projectRoot),
    ]..sort();
  }
}
