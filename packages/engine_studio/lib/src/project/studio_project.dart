import 'dart:io';

import 'package:path/path.dart' as p;

import '../playtest/play_test.dart';

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
            p.basename(file.path) != playtestLevelFile)
          p.relative(file.path, from: root),
    ]..sort();
  }
}
