import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../bootstrap/bootstrap_screen.dart';
import '../bootstrap/update_config.dart';
import '../prefs/recent_projects.dart';
import '../prefs/shortcuts.dart' show studioPrefsFile;
import '../prefs/strings.dart';
import 'git_status.dart';
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

  /// Prefs file for the recent-projects list. Null uses `~/.game_agent/studio_prefs.json`.
  final File? prefsFile;

  const ProjectOpenScreen({
    super.key,
    required this.onOpened,
    this.updateConfig,
    this.prefsFile,
  });

  /// Opens the project's level list. Shared by the app and tests that don't
  /// need to override it.
  static void openProject(BuildContext context, StudioProject project) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(project: project, gitRunner: runGit),
      ),
    );
  }

  @override
  State<ProjectOpenScreen> createState() => _ProjectOpenScreenState();
}

class _ProjectOpenScreenState extends State<ProjectOpenScreen> {
  final _path = TextEditingController();
  String? _error;
  late List<String> _recent;

  File get _prefs => widget.prefsFile ?? studioPrefsFile();

  @override
  void initState() {
    super.initState();
    _recent = loadRecentProjects(_prefs);
  }

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
          title: Text(
            StudioStrings.t('project_open_screen.no_update_server_configured'),
          ),
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

  void _open([String? path]) {
    final target = (path ?? _path.text).trim();
    if (path != null) _path.text = target;
    try {
      final project = StudioProject.open(target);
      rememberRecentProject(project.root, _prefs);
      setState(() {
        _recent = loadRecentProjects(_prefs);
        _error = null;
      });
      widget.onOpened(context, project);
    } on ProjectOpenException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(StudioStrings.t('project_open_screen.open_project')),
        actions: [
          IconButton(
            key: const Key('open-updates'),
            tooltip: StudioStrings.t('bootstrap_screen.updates_and_downloads'),
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
                  decoration: InputDecoration(
                    labelText: StudioStrings.t(
                      'project_open_screen.game_project_folder',
                    ),
                    hintText: '/path/to/my_game',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _open(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton(
                      key: const Key('browse-project'),
                      onPressed: _browse,
                      child: Text(
                        StudioStrings.t('project_open_screen.browse'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('open-project'),
                        onPressed: () => _open(),
                        child: Text(
                          StudioStrings.t('project_open_screen.open'),
                        ),
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
                if (_recent.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    StudioStrings.t('project_open_screen.recent'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      key: const Key('recent-projects'),
                      shrinkWrap: true,
                      itemCount: _recent.length,
                      itemBuilder: (context, i) {
                        final path = _recent[i];
                        return ListTile(
                          key: Key('recent-$i'),
                          dense: true,
                          leading: const Icon(Icons.folder_open, size: 18),
                          title: Text(p.basename(path)),
                          subtitle: Text(
                            path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _open(path),
                        );
                      },
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
