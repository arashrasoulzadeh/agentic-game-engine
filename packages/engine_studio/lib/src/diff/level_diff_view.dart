import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

/// The differences between two levels as a list a designer can read: entities added (green), removed (red) and
/// per-field changes to components, with the old and new value side by side. The data comes from the engine's
/// own [diffLevels], the same comparison `game_agent studio diff` prints.
class LevelDiffView extends StatelessWidget {
  const LevelDiffView({super.key, required this.diff});

  final LevelDiff diff;

  static String _name(LevelEntity e) =>
      e.name ?? '(unnamed ${e.components.keys.join(', ')})';

  @override
  Widget build(BuildContext context) {
    if (diff.isEmpty) {
      return const Center(
        child: Text('No differences.', key: Key('diff-empty')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    Widget line(Key key, IconData icon, Color color, String text) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color, semanticLabel: text),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return ListView(
      key: const Key('diff-list'),
      padding: const EdgeInsets.all(12),
      children: [
        for (final e in diff.added)
          line(
            Key('diff-added-${_name(e)}'),
            Icons.add_circle_outline,
            Colors.green,
            'Added ${_name(e)}',
          ),
        for (final e in diff.removed)
          line(
            Key('diff-removed-${_name(e)}'),
            Icons.remove_circle_outline,
            scheme.error,
            'Removed ${_name(e)}',
          ),
        for (final c in diff.changed)
          for (final comp in c.components)
            if (comp.isAdded)
              line(
                Key('diff-comp-added-${c.name}.${comp.component}'),
                Icons.add_circle_outline,
                Colors.green,
                '${c.name}: added ${comp.component} ${jsonEncode(comp.after)}',
              )
            else if (comp.isRemoved)
              line(
                Key('diff-comp-removed-${c.name}.${comp.component}'),
                Icons.remove_circle_outline,
                scheme.error,
                '${c.name}: removed ${comp.component}',
              )
            else
              for (final f in comp.fields)
                line(
                  Key('diff-field-${c.name}.${comp.component}.$f'),
                  Icons.edit_outlined,
                  scheme.primary,
                  '${c.name}.${comp.component}.$f: ${jsonEncode(comp.before![f])} → ${jsonEncode(comp.after![f])}',
                ),
      ],
    );
  }
}

/// Shows what changed in [after] compared with [before] (usually the saved file against the open editor).
Future<void> showLevelChanges(
  BuildContext context, {
  required LevelDocument before,
  required LevelDocument after,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: const Key('changes-dialog'),
    title: const Text('Unsaved changes'),
    content: SizedBox(
      width: 520,
      height: 320,
      child: LevelDiffView(diff: diffLevels(before, after)),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);
