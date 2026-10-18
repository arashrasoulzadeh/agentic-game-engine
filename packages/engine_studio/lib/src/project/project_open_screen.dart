import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../bootstrap/bootstrap_screen.dart';
import '../bootstrap/update_config.dart';
import '../prefs/shortcuts.dart' show studioPrefsFile;
import 'project_screen.dart';
import 'studio_project.dart';

/// Asks for a game project folder and opens it. Takes a typed path for now: a
/// native folder picker needs a plugin, which is added once package access is
/// available.
class ProjectOpenScreen extends StatefulWidget {
  /// Called with the project once it opens. The app passes [openProject];
  /// tests pass their own.
  final void Function(BuildContext context, StudioProject project) onOpened;

  /// Where the "Updates" window checks. Null reads `updates` from `studio_prefs.json`; tests
  /// pass their own so no real file or network is involved.
  final UpdateConfig? Function()? updateConfig;

  const ProjectOpenScreen({
    super.key,
    required this.onOpened,
    this.updateConfig,
  });

  /// Opens the project's level list. Shared by the app and tests that don't
  /// need to override it.
  static void openProject(BuildContext context, StudioProject project) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProjectScreen(project: project)),
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

  /// Opens the system folder picker and fills the path field with the choice.
  /// Cancelling leaves the field as it was.
  Future<void> _browse() async {
    final folder = await getDirectoryPath();
    if (folder == null) return;
    setState(() {
      _path.text = folder;
      _error = null;
    });
  }

  /// Opens the updates window, or says why it cannot: with no server and key configured the
  /// studio makes no network requests at all.
  void _openUpdates() {
    final config =
        (widget.updateConfig ?? () => UpdateConfig.load(studioPrefsFile()))();
    if (config == null) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('updates-not-configured'),
          title: const Text('No update server configured'),
          content: const Text(
            'Add an "updates" section with "manifestUrl" and "publicKey" to '
            '~/.game_agent/studio_prefs.json. Without the publisher\'s key nothing '
            'downloaded could be verified, so the studio does not check.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BootstrapScreen(
          bootstrapper: config.bootstrapper(studioCacheDir()),
        ),
      ),
    );
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
      appBar: AppBar(
        title: const Text('Open project'),
        actions: [
          IconButton(
            key: const Key('open-updates'),
            tooltip: 'Updates and downloads',
            onPressed: _openUpdates,
            icon: const Icon(Icons.system_update_alt),
          ),
        ],
      ),
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
                Row(
                  children: [
                    OutlinedButton(
                      key: const Key('browse-project'),
                      onPressed: _browse,
                      child: const Text('Browse…'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('open-project'),
                        onPressed: _open,
                        child: const Text('Open'),
                      ),
                    ),
                  ],
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
