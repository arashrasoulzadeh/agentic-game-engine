import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

/// Writes a level to disk. Both writes go through a temporary file and a rename,
/// so a crash mid-save leaves the previous file intact rather than a half-written
/// one.
class LevelSaver {
  const LevelSaver._();

  /// Saves [document] over the level file at [path]. Saves work in progress even
  /// when the level has validation errors: the errors are for the validation
  /// panel to show, not a reason to lose the designer's work.
  static void save(String path, LevelDocument document) {
    _writeAtomically(path, encodeLevelJson(document.toJson()));
  }

  /// Writes a backup of [document] under the project's `.studio/autosave` folder,
  /// leaving the level file itself untouched. Returns the backup's path.
  static String autosave({
    required String projectRoot,
    required String levelPath,
    required LevelDocument document,
  }) {
    final backup = p.join(
      projectRoot,
      '.studio',
      'autosave',
      p.basename(levelPath),
    );
    _writeAtomically(backup, encodeLevelJson(document.toJson()));
    return backup;
  }

  static void _writeAtomically(String path, String contents) {
    final target = File(path)..createSync(recursive: true);
    final temp = File('$path.tmp')..writeAsStringSync(contents, flush: true);
    temp.renameSync(target.path);
  }
}
