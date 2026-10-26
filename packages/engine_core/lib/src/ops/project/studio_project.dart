import 'dart:io';

import 'package:path/path.dart' as p;

/// Why a folder cannot be opened as a game project. [message] is shown to the
/// designer as-is, so it says what to fix rather than just that opening failed.
class ProjectOpenException implements Exception {
  final String message;
  const ProjectOpenException(this.message);

  @override
  String toString() => message;
}

/// True when [root] looks like a `game_agent create` project an agent can open.
///
/// Accepts platformer (`assets/levels`), idle (`assets/idle_game.json`), or
/// strategy (`assets/game_config.json`) layouts — not only levels folders.
bool isGameProjectRoot(String root) {
  if (!File(p.join(root, 'pubspec.yaml')).existsSync()) return false;
  if (Directory(p.join(root, 'assets', 'levels')).existsSync()) return true;
  if (File(p.join(root, 'assets', 'idle_game.json')).existsSync()) return true;
  if (File(p.join(root, 'assets', 'game_config.json')).existsSync()) return true;
  return Directory(p.join(root, 'assets')).existsSync();
}

/// Immediate child folders of [path] that themselves look like game projects.
///
/// Used when the designer (or agent) picks a repo root that wraps the Flutter
/// app in a `game/` subdirectory — Mobarez-style layouts — instead of the
/// `pubspec.yaml` folder itself.
List<String> nestedGameProjectRoots(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  final found = <String>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    if (isGameProjectRoot(entity.path)) found.add(entity.path);
  }
  found.sort((a, b) {
    // Prefer the conventional `game/` wrapper used by monorepo-style titles.
    final aGame = p.basename(a) == 'game';
    final bGame = p.basename(b) == 'game';
    if (aGame != bGame) return aGame ? -1 : 1;
    return a.compareTo(b);
  });
  return found;
}

/// Resolves [path] to the folder that actually holds `pubspec.yaml` + assets.
///
/// Returns [path] when it is already a game root; otherwise the best nested
/// candidate (preferring `game/`). Throws [ProjectOpenException] when nothing
/// usable is found (or several siblings look equally valid).
String resolveGameProjectRoot(String path) {
  if (isGameProjectRoot(path)) return path;
  final nested = nestedGameProjectRoots(path);
  if (nested.length == 1) return nested.first;
  if (nested.length > 1) {
    // Prefer `game/` when present among several; otherwise ask the user.
    final game = nested.where((c) => p.basename(c) == 'game').toList();
    if (game.length == 1) return game.first;
    final names = nested.map(p.basename).join(', ');
    throw ProjectOpenException(
      '"$path" is not a game project itself, but several child folders '
      'look like ones ($names). Open one of those folders instead.',
    );
  }
  if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
    throw ProjectOpenException(
      '"$path" is not a game project: no pubspec.yaml '
      '(and no child like game/ with one either).',
    );
  }
  throw ProjectOpenException(
    '"$path" has no game assets (need assets/levels, '
    'assets/idle_game.json, or assets/game_config.json).',
  );
}

/// A game project on disk: the folder `game_agent create` made, which holds a
/// `pubspec.yaml` and game content under `assets/` (levels, idle definition,
/// and/or `game_config.json`).
class StudioProject {
  final String root;

  const StudioProject._(this.root);

  /// Opens [path] as a project. Throws [ProjectOpenException] when the folder is
  /// missing or is not a recognisable game project.
  ///
  /// When [path] is a wrapper repo (pubspec lives in a child such as `game/`),
  /// opens that child so Mobarez-style layouts work from the folder picker.
  factory StudioProject.open(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw ProjectOpenException('"$path" does not exist.');
    }
    final resolved = resolveGameProjectRoot(path);
    return StudioProject._(p.normalize(p.absolute(resolved)));
  }

  /// The level files in this project, sorted by path, relative to [root].
  /// Empty when the project has no `assets/levels` folder (idle / strategy).
  List<String> levelPaths() {
    final dir = Directory(p.join(root, 'assets', 'levels'));
    if (!dir.existsSync()) return [];
    return [
      for (final file in dir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.json') &&
            p.basename(file.path) != 'playtest.level.json')
          p.relative(file.path, from: root),
    ]..sort();
  }

  /// The prefabs in this project (`prefabs/*.json`, where the studio saves them), sorted and relative to [root].
  List<String> prefabPaths() {
    final dir = Directory(p.join(root, 'prefabs'));
    if (!dir.existsSync()) return [];
    return [
      for (final file in dir.listSync().whereType<File>())
        if (file.path.endsWith('.json')) p.relative(file.path, from: root),
    ]..sort();
  }

  /// The visual-scripting graphs in this project (`graphs/*.json`), sorted and
  /// relative to [root]. Empty until the designer creates one.
  List<String> graphPaths() {
    final dir = Directory(p.join(root, 'graphs'));
    if (!dir.existsSync()) return [];
    return [
      for (final file in dir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.json')) p.relative(file.path, from: root),
    ]..sort();
  }

  /// A path for a new graph that doesn't exist yet: `graphs/graph1.json`, then
  /// `graph2.json`... The folder is created by the graph editor on first save.
  String nextGraphPath() {
    var n = 1;
    while (File(p.join(root, 'graphs', 'graph$n.json')).existsSync()) {
      n++;
    }
    return p.join('graphs', 'graph$n.json');
  }

  /// The project's source files a designer can edit as text: Dart under `lib/`,
  /// sorted and relative to [root]. Level JSON is listed separately by [levelPaths].
  List<String> codeFiles() {
    final dir = Directory(p.join(root, 'lib'));
    if (!dir.existsSync()) return [];
    return [
      for (final file in dir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart')) p.relative(file.path, from: root),
    ]..sort();
  }
}
