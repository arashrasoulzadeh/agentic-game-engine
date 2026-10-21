import 'dart:convert';
import 'dart:io';

/// Writes save files so that a crash, a full disk or a power cut mid-write can never leave the player
/// with nothing: the new data goes to a temporary file first, and only a complete write replaces the
/// real one. The previous good save is kept as `<path>.bak`.
class AtomicSave {
  AtomicSave(this.path);

  /// The save file.
  final String path;

  File get _file => File(path);
  File get _backup => File('$path.bak');
  File get _temp => File('$path.tmp');

  /// Stores [json]. The old file becomes the backup; the new one appears whole or not at all.
  void write(Map<String, dynamic> json) {
    _temp
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(json), flush: true);
    if (_file.existsSync()) {
      _file.copySync(_backup.path);
    }
    _temp.renameSync(path);
  }

  /// The newest readable save, or null if there is none. A corrupt or half-written main file falls back to
  /// the backup, so the player loses at most the last save interval.
  Map<String, dynamic>? read() => _try(_file) ?? _try(_backup);

  /// Whether the last [read] had to use the backup (the main file was unreadable).
  bool get mainIsReadable => _try(_file) != null;

  Map<String, dynamic>? _try(File f) {
    try {
      if (!f.existsSync()) return null;
      final json = jsonDecode(f.readAsStringSync());
      return json is Map ? json.cast<String, dynamic>() : null;
    } on Object {
      return null;
    }
  }
}
