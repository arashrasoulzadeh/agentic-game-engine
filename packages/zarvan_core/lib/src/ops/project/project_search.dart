import 'dart:io';

import 'package:path/path.dart' as p;

import 'find_replace.dart';
import 'project_tree.dart';

/// One occurrence of a search query in a project file.
class ProjectMatch {
  final String relativePath;
  final int line;
  final int character;
  final String lineText;

  const ProjectMatch(
    this.relativePath,
    this.line,
    this.character,
    this.lineText,
  );
}

/// The kinds of file worth searching: code, data, and level JSON. Images and
/// other binary-ish files are skipped, since a text search in them is meaningless.
const _searchableKinds = {FileKind.code, FileKind.data, FileKind.level};

/// Every occurrence of [query] across [entries]' files under [root], in tree
/// order. A file that fails to read as text (missing, binary, permissions) is
/// skipped rather than failing the whole search.
List<ProjectMatch> searchProject(
  String root,
  List<ProjectEntry> entries,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];
  final matches = <ProjectMatch>[];
  for (final entry in entries) {
    if (entry.isDirectory || !_searchableKinds.contains(kindOf(entry))) {
      continue;
    }
    String text;
    try {
      text = File(p.join(root, entry.relativePath)).readAsStringSync();
    } on Object {
      continue;
    }
    final lines = text.split('\n');
    for (var line = 0; line < lines.length; line++) {
      for (final match in findMatches(
        lines[line],
        query,
        caseSensitive: caseSensitive,
      )) {
        matches.add(
          ProjectMatch(entry.relativePath, line, match.start, lines[line]),
        );
      }
    }
  }
  return matches;
}
