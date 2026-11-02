import 'package:flutter/material.dart';

import '../prefs/strings.dart';
import 'git_status.dart';

/// Left-rail list of git-changed files, a text diff, and a commit box.
class GitPanel extends StatefulWidget {
  final String projectRoot;
  final Map<String, GitChange> changes;
  final GitRunner? gitRunner;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final ValueChanged<String> onOpenFile;

  const GitPanel({
    super.key,
    required this.projectRoot,
    required this.changes,
    required this.gitRunner,
    required this.onClose,
    required this.onRefresh,
    required this.onOpenFile,
  });

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  final _message = TextEditingController();
  String? _diffPath;
  String _diff = '';
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _showDiff(String path) async {
    setState(() {
      _diffPath = path;
      _diff = '';
    });
    final text = await readGitDiff(
      widget.projectRoot,
      path,
      run: widget.gitRunner,
    );
    if (!mounted) return;
    setState(() => _diff = text);
  }

  Future<void> _commit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await commitGitAll(
      widget.projectRoot,
      _message.text,
      run: widget.gitRunner,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result.output.trim().isEmpty
          ? (result.ok
                ? StudioStrings.t('git.committed')
                : StudioStrings.t('git.commitFailed'))
          : result.output.trim();
      if (result.ok) _message.clear();
    });
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.changes.keys.toList()..sort();
    return Column(
      key: const Key('git-panel'),
      children: [
        ListTile(
          dense: true,
          title: Text(StudioStrings.t('git.title')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('git-panel-refresh'),
                tooltip: StudioStrings.t('project.gitRefresh'),
                iconSize: 16,
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                key: const Key('git-panel-close'),
                tooltip: StudioStrings.t('project.close'),
                iconSize: 16,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: paths.isEmpty
              ? Center(
                  key: const Key('git-panel-empty'),
                  child: Text(StudioStrings.t('git.empty')),
                )
              : ListView(
                  key: const Key('git-panel-list'),
                  children: [
                    for (final path in paths)
                      ListTile(
                        key: Key('git-panel-file-$path'),
                        dense: true,
                        selected: path == _diffPath,
                        leading: Text(
                          widget.changes[path]!.badge,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: _color(widget.changes[path]!),
                          ),
                        ),
                        title: Text(
                          path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          widget.onOpenFile(path);
                          _showDiff(path);
                        },
                      ),
                  ],
                ),
        ),
        if (_diffPath != null)
          SizedBox(
            height: 120,
            child: ColoredBox(
              color: const Color(0xFF1E1E1E),
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  SelectableText(
                    _diff.isEmpty ? StudioStrings.t('git.noDiff') : _diff,
                    key: const Key('git-panel-diff'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFE0E0E0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(
              _status!,
              key: const Key('git-panel-status'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            children: [
              TextField(
                key: const Key('git-commit-message'),
                controller: _message,
                enabled: !_busy,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: StudioStrings.t('git.message'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('git-commit'),
                  onPressed: _busy ? null : _commit,
                  child: Text(StudioStrings.t('git.commit')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _color(GitChange change) {
    switch (change) {
      case GitChange.added:
      case GitChange.untracked:
        return Colors.green;
      case GitChange.deleted:
      case GitChange.conflicted:
        return Colors.red;
      case GitChange.renamed:
        return Colors.blue;
      case GitChange.modified:
        return Colors.orange;
    }
  }
}
