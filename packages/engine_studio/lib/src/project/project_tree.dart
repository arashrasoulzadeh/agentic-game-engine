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

/// The types the file manager can filter by. [all] shows the tree; the others show
/// matching files as a flat list.
enum FileKind { all, code, level, image, data, other }

/// Which filter a file belongs to. Levels are JSON under `assets/levels`, so they are
/// told apart from other JSON; images are the formats the viewer can show.
FileKind kindOf(ProjectEntry entry) {
  if (entry.isDirectory) return FileKind.other;
  final name = entry.name.toLowerCase();
  if (name.endsWith('.dart')) return FileKind.code;
  if (name.endsWith('.json') &&
      entry.relativePath.startsWith('assets/levels/')) {
    return FileKind.level;
  }
  if (_imageExtensions.any(name.endsWith)) return FileKind.image;
  if (name.endsWith('.json') ||
      name.endsWith('.yaml') ||
      name.endsWith('.yml')) {
    return FileKind.data;
  }
  return FileKind.other;
}

const _imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];

/// The entries the tree shows: top-level entries, plus the children of each folder
/// that is in [expanded]. Everything starts closed, so a window opens showing only
/// the project's top level.
List<ProjectEntry> visibleTree(List<ProjectEntry> all, Set<String> expanded) {
  return [
    for (final entry in all)
      if (_parentsExpanded(entry, expanded)) entry,
  ];
}

bool _parentsExpanded(ProjectEntry entry, Set<String> expanded) {
  var parent = p.dirname(entry.relativePath);
  while (parent != '.') {
    if (!expanded.contains(parent)) return false;
    parent = p.dirname(parent);
  }
  return true;
}

/// The files of one [kind], flat and in tree order, for the filtered view. The
/// [FileKind.all] filter is not a kind of file, so it returns nothing here.
List<ProjectEntry> filterFiles(List<ProjectEntry> all, FileKind kind) {
  if (kind == FileKind.all) return const [];
  return [
    for (final entry in all)
      if (!entry.isDirectory && kindOf(entry) == kind) entry,
  ];
}
