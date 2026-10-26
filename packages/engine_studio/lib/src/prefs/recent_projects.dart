import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'shortcuts.dart' show studioPrefsFile;

const _recentKey = 'recentProjects';
const _maxRecent = 8;

/// Absolute paths of projects the designer opened recently, newest first.
List<String> loadRecentProjects([File? prefsFile]) {
  final file = prefsFile ?? studioPrefsFile();
  try {
    if (!file.existsSync()) return const [];
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map) return const [];
    final raw = json[_recentKey];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  } on Object {
    return const [];
  }
}

/// Records [projectRoot] at the front of the recent list in studio prefs.
void rememberRecentProject(String projectRoot, [File? prefsFile]) {
  final file = prefsFile ?? studioPrefsFile();
  final absolute = p.normalize(p.absolute(projectRoot));
  Map<String, dynamic> json = {};
  try {
    if (file.existsSync()) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        json = Map<String, dynamic>.from(decoded);
      }
    }
  } on Object {
    json = {};
  }
  final recent = <String>[
    absolute,
    for (final path in loadRecentProjects(file))
      if (path != absolute) path,
  ];
  json[_recentKey] = recent.take(_maxRecent).toList();
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(json),
  );
}
