import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';

import '../level/level_editor.dart';
import 'project_stores.dart';
import 'tile_pattern.dart';
import '../prefs/strings.dart';

/// The project's brushes: tile patterns and prefabs, usable in any level. Picking one
/// switches the editor to the stamp tool; "Save as prefab" turns the selected entity
/// into a prefab brush; "New tile brush" takes a typed pattern.
class BrushPanel extends StatefulWidget {
  final LevelEditor editor;
  final String projectRoot;

  /// Called after the active brush or tool changes, so the screen can redraw.
  final VoidCallback onChanged;

  const BrushPanel({
    super.key,
    required this.editor,
    required this.projectRoot,
    required this.onChanged,
  });

  @override
  State<BrushPanel> createState() => _BrushPanelState();
}

class _BrushPanelState extends State<BrushPanel> {
  late BrushLibrary _library;
  String? _message;

  BrushStore get _store => BrushStore(widget.projectRoot);

  @override
  void initState() {
    super.initState();
    _library = _store.load();
  }

  void _pick(Brush brush) {
    widget.editor
      ..activeBrush = brush
      ..tool = EditorTool.stamp;
    widget.onChanged();
    setState(() => _message = null);
  }

  void _remove(Brush brush) {
    _library.remove(brush.name);
    if (widget.editor.activeBrush?.name == brush.name) {
      widget.editor.activeBrush = null;
    }
    _store.save(_library);
    widget.onChanged();
    setState(() {});
  }

  Future<String?> _ask(String title, String hint, {int lines = 1}) {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextPrompt(title: title, hint: hint, lines: lines),
    );
  }

  Future<void> _newTileBrush() async {
    final name = await _ask('Brush name', 'e.g. ledge');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final text = await _ask(
      'Pattern',
      '1 1 1\n_ 2 _  (one row per line; _ leaves a cell alone; 0 erases)',
      lines: 4,
    );
    if (text == null || !mounted) return;
    try {
      _library.add(
        TileBrush(name: name.trim(), pattern: parseTilePattern(text)),
      );
      _store.save(_library);
      setState(() => _message = null);
    } on FormatException catch (e) {
      setState(() => _message = e.message);
    }
  }

  Future<void> _saveSelectionAsPrefab() async {
    if (widget.editor.selected == null) {
      setState(() => _message = 'Select an entity first.');
      return;
    }
    final name = await _ask('Prefab name', 'letters, digits, _ and -');
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (!PrefabStore.isValidName(trimmed)) {
      setState(
        () => _message =
            'A prefab name may only use letters, digits, "_" and "-".',
      );
      return;
    }
    final prefab = widget.editor.prefabFromSelection(trimmed)!;
    final path = PrefabStore(widget.projectRoot).save(prefab);
    _library.add(PrefabBrush(name: trimmed, prefabPath: path));
    _store.save(_library);
    setState(() => _message = 'Saved $path');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.editor.activeBrush;
    return Container(
      key: const Key('brush-panel'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text('Brushes', style: theme.textTheme.labelLarge),
          ),
          Wrap(
            children: [
              TextButton(
                key: const Key('brush-new-tiles'),
                onPressed: _newTileBrush,
                child: Text(StudioStrings.t('brush_panel.new_tile_brush')),
              ),
              TextButton(
                key: const Key('brush-save-prefab'),
                onPressed: _saveSelectionAsPrefab,
                child: Text(StudioStrings.t('brush_panel.save_as_prefab')),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _message!,
                key: const Key('brush-message'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_library.brushes.isEmpty)
            const ListTile(
              dense: true,
              title: Text('No brushes yet.', key: Key('brush-empty')),
            ),
          for (final brush in _library.brushes)
            ListTile(
              key: Key('brush-${brush.name}'),
              dense: true,
              selected:
                  identical(active, brush) ||
                  (active?.name == brush.name &&
                      active.runtimeType == brush.runtimeType),
              leading: Icon(
                brush is TileBrush ? Icons.grid_4x4 : Icons.widgets_outlined,
                size: 18,
              ),
              title: Text(brush.name),
              subtitle: Text(
                brush is TileBrush
                    ? '${brush.width}×${brush.height} tiles'
                    : 'prefab',
              ),
              trailing: IconButton(
                key: Key('brush-delete-${brush.name}'),
                tooltip: StudioStrings.t('brush_panel.delete_brush'),
                iconSize: 16,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(brush),
              ),
              onTap: () => _pick(brush),
            ),
        ],
      ),
    );
  }
}

/// A one-field dialog that owns its controller (disposed with the dialog, after its
/// close animation).
class _TextPrompt extends StatefulWidget {
  final String title;
  final String hint;
  final int lines;
  const _TextPrompt({
    required this.title,
    required this.hint,
    required this.lines,
  });

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('prompt-field'),
        controller: _controller,
        autofocus: true,
        minLines: widget.lines,
        maxLines: widget.lines,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(StudioStrings.t('common.cancel')),
        ),
        TextButton(
          key: const Key('prompt-ok'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
