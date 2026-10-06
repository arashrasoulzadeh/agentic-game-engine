import 'dart:io';

import 'package:path/path.dart' as p;

/// Folders the file manager leaves out: generated output, tool caches, and version
/// control. They change constantly and a designer never edits them.
const _hiddenFolders = {
  'build',
  '.dart_tool',
  '.git',
  '.idea',
  '.studio',
  'Pods',
};

/// One entry in the project's file tree: a folder, or a file, relative to the project
/// root.
class ProjectEntry {
  final String relativePath;
  final bool isDirectory;

  const ProjectEntry(this.relativePath, {required this.isDirectory});

  String get name => p.basename(relativePath);

  /// How many folders deep this entry sits, for indenting it in the tree.
  int get depth => p.split(relativePath).length - 1;
}

/// Lists a project's files and folders for the file manager, folders before files
/// at each level, both sorted. Hidden and generated folders are skipped.
List<ProjectEntry> listProjectTree(String root) {
  final entries = <ProjectEntry>[];
  void walk(String relative) {
    final dir = Directory(p.join(root, relative));
    if (!dir.existsSync()) return;
    final children = dir.listSync().toList()
      ..sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p.basename(a.path).compareTo(p.basename(b.path));
      });
    for (final child in children) {
      final name = p.basename(child.path);
      if (name.startsWith('.') && child is Directory) continue;
      final childRelative = relative.isEmpty ? name : p.join(relative, name);
      if (child is Directory) {
        if (_hiddenFolders.contains(name)) continue;
        entries.add(ProjectEntry(childRelative, isDirectory: true));
        walk(childRelative);
      } else if (!name.startsWith('.')) {
        entries.add(ProjectEntry(childRelative, isDirectory: false));
      }
    }
  }

  walk('');
  return entries;
}
