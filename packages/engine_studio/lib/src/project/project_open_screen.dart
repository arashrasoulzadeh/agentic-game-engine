import 'package:flutter/material.dart';

import '../level/level_screen.dart';
import 'studio_project.dart';

/// Asks for a game project folder and opens it. Takes a typed path for now: a
/// native folder picker needs a plugin, which is added once package access is
/// available.
class ProjectOpenScreen extends StatefulWidget {
  /// Called with the project once it opens. The app passes [openFirstLevel];
  /// tests pass their own.
  final void Function(BuildContext context, StudioProject project) onOpened;

  const ProjectOpenScreen({super.key, required this.onOpened});

  /// Opens the project's first level, or shows a message when there are none,
  /// since an empty level screen would only be confusing.
  static void openFirstLevel(BuildContext context, StudioProject project) {
    final levels = project.levelPaths();
    if (levels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This project has no levels yet.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LevelScreen(levelPath: '${project.root}/${levels.first}'),
      ),
    );
  }

  @override
  State<ProjectOpenScreen> createState() => _ProjectOpenScreenState();
}

class _ProjectOpenScreenState extends State<ProjectOpenScreen> {
  final _path = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _open() {
    try {
      final project = StudioProject.open(_path.text.trim());
      widget.onOpened(context, project);
    } on ProjectOpenException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open project')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('project-path'),
                  controller: _path,
                  decoration: const InputDecoration(
                    labelText: 'Game project folder',
                    hintText: '/path/to/my_game',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _open(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('open-project'),
                  onPressed: _open,
                  child: const Text('Open'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('open-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
