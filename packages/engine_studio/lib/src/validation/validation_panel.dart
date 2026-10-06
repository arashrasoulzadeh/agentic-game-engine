import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import '../level/level_editor.dart';

/// Lists the level's problems as the validator reports them, live as the level is
/// edited. Clicking a problem selects the entity it belongs to, so the inspector
/// opens on the broken component. Collapsed by default so it does not crowd the
/// canvas when a level is clean.
class ValidationPanel extends StatelessWidget {
  final LevelEditor editor;

  /// Called after a problem's entity is selected, so the screen can redraw.
  final VoidCallback onSelect;

  const ValidationPanel({
    super.key,
    required this.editor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final issues = editor.issues;
    final errors = issues
        .where((i) => i.severity == IssueSeverity.error)
        .length;
    final warnings = issues.length - errors;
    final theme = Theme.of(context);

    return ExpansionTile(
      key: const Key('validation-panel'),
      title: Text(
        issues.isEmpty
            ? 'No problems'
            : 'Problems: $errors error(s), $warnings warning(s)',
        style: TextStyle(color: errors > 0 ? theme.colorScheme.error : null),
      ),
      initiallyExpanded: false,
      children: [
        if (issues.isEmpty)
          const ListTile(
            dense: true,
            title: Text('This level has no problems.'),
          ),
        for (var i = 0; i < issues.length; i++)
          ListTile(
            key: Key('problem-$i'),
            dense: true,
            leading: Icon(
              issues[i].severity == IssueSeverity.error
                  ? Icons.error_outline
                  : Icons.warning_amber_outlined,
              color: issues[i].severity == IssueSeverity.error
                  ? theme.colorScheme.error
                  : theme.colorScheme.tertiary,
            ),
            title: Text(issues[i].toString()),
            onTap: issues[i].entityIndex < 0
                ? null
                : () {
                    editor.selectIndex(issues[i].entityIndex);
                    onSelect();
                  },
          ),
      ],
    );
  }
}
