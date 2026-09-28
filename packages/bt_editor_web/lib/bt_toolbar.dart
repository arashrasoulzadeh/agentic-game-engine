import 'package:flutter/material.dart';

class BTToolbarActions {
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onNew;
  final VoidCallback onSave;

  const BTToolbarActions({
    required this.onExport,
    required this.onImport,
    required this.onNew,
    required this.onSave,
  });
}

class BTToolbar extends StatelessWidget {
  final BTToolbarActions actions;

  const BTToolbar({
    super.key,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.add,
            label: 'New',
            tooltip: 'New Behavior Tree (Ctrl+N)',
            onPressed: actions.onNew,
          ),
          _ToolbarButton(
            icon: Icons.save,
            label: 'Save',
            tooltip: 'Save/Export JSON (Ctrl+S)',
            onPressed: actions.onSave,
          ),
          _ToolbarButton(
            icon: Icons.file_upload,
            label: 'Export',
            tooltip: 'Export JSON',
            onPressed: actions.onExport,
          ),
          _ToolbarButton(
            icon: Icons.file_download,
            label: 'Import',
            tooltip: 'Import JSON',
            onPressed: actions.onImport,
          ),
          const SizedBox(width: 24),
          _ToolbarButton(
            icon: Icons.undo,
            label: 'Undo',
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: () {},
            enabled: false,
          ),
          _ToolbarButton(
            icon: Icons.redo,
            label: 'Redo',
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: () {},
            enabled: false,
          ),
          const Spacer(),
          _ToolbarButton(
            icon: Icons.zoom_out,
            label: '',
            tooltip: 'Zoom Out',
            onPressed: () {},
          ),
          _ToolbarButton(
            icon: Icons.zoom_in,
            label: '',
            tooltip: 'Zoom In',
            onPressed: () {},
          ),
          _ToolbarButton(
            icon: Icons.fit_screen,
            label: '',
            tooltip: 'Fit to View',
            onPressed: () {},
          ),
          const SizedBox(width: 24),
          _ToolbarButton(
            icon: Icons.check_circle_outline,
            label: 'Validate',
            tooltip: 'Validate Graph',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool enabled;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 20),
        label: label.isNotEmpty ? Text(label) : const SizedBox.shrink(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: enabled
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
    );
  }
}