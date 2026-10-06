import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../code/code_editor_screen.dart';
import '../level/level_screen.dart';
import 'image_view.dart';
import 'project_tree.dart';
import 'studio_project.dart';

/// A project window: the file manager on the left, and the file you pick open on
/// the right. Level files open in the level editor, and every other file opens in
/// the code editor. Nothing is opened until you pick it, so the window starts empty.
class ProjectScreen extends StatefulWidget {
  final StudioProject project;

  /// Passed to each code editor the window opens. Tests turn it off.
  final bool useLanguageServer;

  const ProjectScreen({
    super.key,
    required this.project,
    this.useLanguageServer = true,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  String? _open;

  /// Folders the designer has expanded. Empty at start, so the tree opens closed.
  final Set<String> _expanded = {};
  FileKind _filter = FileKind.all;

  @override
  Widget build(BuildContext context) {
    final all = listProjectTree(widget.project.root);
    final shown = _filter == FileKind.all
        ? visibleTree(all, _expanded)
        : filterFiles(all, _filter);
    return Scaffold(
      appBar: AppBar(title: Text(p.basename(widget.project.root))),
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Column(
              children: [
                _FilterBar(
                  selected: _filter,
                  onChanged: (kind) => setState(() => _filter = kind),
                ),
                Expanded(
                  child: ListView(
                    key: const Key('file-tree'),
                    children: [for (final entry in shown) _row(entry)],
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  /// One row of the tree or of a filtered list. A folder toggles open or closed; a
  /// file opens on the right. In a filtered list the path is shown, since names
  /// repeat across folders.
  Widget _row(ProjectEntry entry) {
    final filtered = _filter != FileKind.all;
    return ListTile(
      key: Key('file-${entry.relativePath}'),
      dense: true,
      selected: entry.relativePath == _open,
      contentPadding: EdgeInsets.only(
        left: filtered ? 12 : 12.0 + entry.depth * 14,
        right: 8,
      ),
      leading: entry.isDirectory
          ? Icon(
              _expanded.contains(entry.relativePath)
                  ? Icons.expand_more
                  : Icons.chevron_right,
              size: 18,
            )
          : Icon(_iconFor(entry.name), size: 18),
      title: Text(
        filtered ? entry.relativePath : entry.name,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => setState(() {
        if (entry.isDirectory) {
          if (!_expanded.remove(entry.relativePath)) {
            _expanded.add(entry.relativePath);
          }
        } else {
          _open = entry.relativePath;
        }
      }),
    );
  }

  Widget _content() {
    final open = _open;
    if (open == null) {
      return const Center(
        key: Key('no-file-open'),
        child: Text('Pick a file on the left to open it.'),
      );
    }
    final fullPath = p.join(widget.project.root, open);
    if (open.startsWith('assets/levels/') && open.endsWith('.json')) {
      return LevelScreen(
        key: ValueKey(fullPath),
        levelPath: fullPath,
        projectRoot: widget.project.root,
      );
    }
    if (kindOf(ProjectEntry(open, isDirectory: false)) == FileKind.image) {
      return ImageView(key: ValueKey(fullPath), filePath: fullPath);
    }
    if (File(fullPath).existsSync()) {
      return CodeEditorScreen(
        key: ValueKey(fullPath),
        filePath: fullPath,
        projectRoot: widget.project.root,
        useLanguageServer: widget.useLanguageServer,
      );
    }
    return const Center(child: Text('That file no longer exists.'));
  }

  IconData _iconFor(String name) {
    if (name.endsWith('.dart')) return Icons.code;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.png')) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

/// The type filter above the file tree. "All" shows the tree; a type shows just the
/// files of that type.
class _FilterBar extends StatelessWidget {
  final FileKind selected;
  final ValueChanged<FileKind> onChanged;

  const _FilterBar({required this.selected, required this.onChanged});

  static const _labels = {
    FileKind.all: 'All',
    FileKind.code: 'Code',
    FileKind.level: 'Levels',
    FileKind.image: 'Images',
    FileKind.data: 'Data',
    FileKind.other: 'Other',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in _labels.entries)
            ChoiceChip(
              key: Key('filter-${entry.key.name}'),
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onChanged(entry.key),
            ),
        ],
      ),
    );
  }
}
