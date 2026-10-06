import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../code/code_editor_screen.dart';
import '../level/level_screen.dart';
import 'project_tree.dart';
import 'studio_project.dart';

/// A project window: the file manager on the left, and the file you pick open on
/// the right. Level files open in the level editor, and every other file opens in
/// the code editor. Nothing is opened until you pick it, so the window starts empty.
class ProjectScreen extends StatefulWidget {
  final StudioProject project;

  const ProjectScreen({super.key, required this.project});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    final entries = listProjectTree(widget.project.root);
    return Scaffold(
      appBar: AppBar(title: Text(p.basename(widget.project.root))),
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: ListView(
              key: const Key('file-tree'),
              children: [
                for (final entry in entries)
                  ListTile(
                    key: Key('file-${entry.relativePath}'),
                    dense: true,
                    selected: entry.relativePath == _open,
                    contentPadding: EdgeInsets.only(
                      left: 12.0 + entry.depth * 14,
                      right: 8,
                    ),
                    leading: Icon(
                      entry.isDirectory
                          ? Icons.folder_outlined
                          : _iconFor(entry.name),
                      size: 18,
                    ),
                    title: Text(entry.name, overflow: TextOverflow.ellipsis),
                    onTap: entry.isDirectory
                        ? null
                        : () => setState(() => _open = entry.relativePath),
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
    if (File(fullPath).existsSync()) {
      return CodeEditorScreen(
        key: ValueKey(fullPath),
        filePath: fullPath,
        projectRoot: widget.project.root,
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
