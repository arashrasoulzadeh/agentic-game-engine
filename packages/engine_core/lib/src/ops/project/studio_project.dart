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

/// A game project on disk: the folder `game_agent create` made, which holds a
/// `pubspec.yaml` and an `assets/levels` folder.
class StudioProject {
  final String root;

  const StudioProject._(this.root);

  /// Opens [path] as a project. Throws [ProjectOpenException] when the folder is
  /// missing, is not a game project, or has no levels folder.
  factory StudioProject.open(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw ProjectOpenException('"$path" does not exist.');
    }
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      throw ProjectOpenException(
        '"$path" is not a game project: no pubspec.yaml.',
      );
    }
    if (!Directory(p.join(path, 'assets', 'levels')).existsSync()) {
      throw ProjectOpenException(
        '"$path" has no assets/levels folder to edit.',
      );
    }
    return StudioProject._(p.normalize(p.absolute(path)));
  }

  /// The level files in this project, sorted by path, relative to [root].
  List<String> levelPaths() {
    final dir = Directory(p.join(root, 'assets', 'levels'));
    return [
      for (final file in dir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.json') &&
            p.basename(file.path) != 'playtest.level.json')
          p.relative(file.path, from: root),
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
