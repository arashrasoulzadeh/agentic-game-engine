import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../inspector/inspector_panel.dart';
import 'level_canvas.dart';
import 'level_saver.dart';
import 'level_editor.dart';

/// Edits one level file in memory. A toolbar picks the tool; gestures on the
/// canvas go to the [LevelEditor], which turns them into undoable commands. Saving
/// comes in phase 3.11.
class LevelScreen extends StatefulWidget {
  final String levelPath;

  /// The project this level belongs to. Autosave backups go under it; without it
  /// there is nowhere to back up to, so autosave is off.
  final String? projectRoot;

  /// How often a dirty level is backed up. Null turns autosave off.
  final Duration? autosaveInterval;

  const LevelScreen({
    super.key,
    required this.levelPath,
    this.projectRoot,
    this.autosaveInterval = const Duration(seconds: 30),
  });

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen> {
  LevelEditor? _editor;
  String? _loadError;
  Timer? _autosave;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  String? _saveError;

  @override
  void initState() {
    super.initState();
    try {
      final json =
          jsonDecode(File(widget.levelPath).readAsStringSync())
              as Map<String, dynamic>;
      _editor = LevelEditor(LevelDocument.fromJson(json));
    } on Object catch (e) {
      _loadError = 'Could not open ${widget.levelPath}: $e';
    }
    final interval = widget.autosaveInterval;
    if (interval != null && widget.projectRoot != null) {
      _autosave = Timer.periodic(interval, (_) => _backUpIfDirty());
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Writes the level file. A failure stays on screen rather than being lost, and
  /// the level stays dirty so nothing is marked saved that was not.
  void _save() {
    final editor = _editor;
    if (editor == null) return;
    try {
      LevelSaver.save(widget.levelPath, editor.document);
      editor.markSaved();
      setState(() => _saveError = null);
    } on FileSystemException catch (e) {
      setState(() => _saveError = 'Could not save: ${e.message}');
    }
  }

  void _backUpIfDirty() {
    final editor = _editor;
    final root = widget.projectRoot;
    if (editor == null || root == null || !editor.isDirty) return;
    try {
      LevelSaver.autosave(
        projectRoot: root,
        levelPath: widget.levelPath,
        document: editor.document,
      );
    } on FileSystemException {
      // A missed backup is not worth interrupting the designer. The next tick
      // retries, and the explicit save reports its own failures.
    }
  }

  /// Runs an editor action and rebuilds, so the canvas and status bar show it.
  void _edit(void Function(LevelEditor editor) action) {
    setState(() => action(_editor!));
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (editor == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Level')),
        body: Center(child: Text(_loadError!, key: const Key('level-error'))),
      );
    }

    final title = widget.levelPath.split(Platform.pathSeparator).last;
    final saveShortcut = {
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
    };
    return CallbackShortcuts(
      bindings: saveShortcut,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Text(title),
                if (editor.isDirty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '•',
                      key: const Key('dirty-marker'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('save'),
                tooltip: 'Save (Cmd/Ctrl+S)',
                onPressed: editor.isDirty ? _save : null,
                icon: const Icon(Icons.save_outlined),
              ),
              IconButton(
                key: const Key('undo'),
                tooltip: editor.history.undoLabel == null
                    ? 'Nothing to undo'
                    : 'Undo ${editor.history.undoLabel}',
                onPressed: editor.history.canUndo
                    ? () => _edit((e) => e.undo())
                    : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                key: const Key('redo'),
                tooltip: editor.history.redoLabel == null
                    ? 'Nothing to redo'
                    : 'Redo ${editor.history.redoLabel}',
                onPressed: editor.history.canRedo
                    ? () => _edit((e) => e.redo())
                    : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                key: const Key('delete-selected'),
                tooltip: 'Delete selected entity',
                onPressed: editor.selected == null
                    ? null
                    : () => _edit((e) => e.deleteSelected()),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: Column(
            children: [
              _Toolbar(
                tool: editor.tool,
                onChanged: (tool) => _edit((e) => e.tool = tool),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _vertical,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _vertical,
                          child: Scrollbar(
                            controller: _horizontal,
                            thumbVisibility: true,
                            notificationPredicate: (n) => n.depth == 1,
                            child: SingleChildScrollView(
                              controller: _horizontal,
                              scrollDirection: Axis.horizontal,
                              child: GestureDetector(
                                key: const Key('level-canvas'),
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (details) =>
                                    _edit((e) => e.tap(details.localPosition)),
                                onPanStart: (details) => _edit(
                                  (e) => e.dragStart(details.localPosition),
                                ),
                                onPanUpdate: (details) => _edit(
                                  (e) => e.dragUpdate(details.localPosition),
                                ),
                                onPanEnd: (_) =>
                                    _edit((e) => e.dragEnd(_lastPoint(e))),
                                child: CustomPaint(
                                  size: _canvasSize(editor),
                                  painter: LevelCanvasPainter(editor: editor),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    InspectorPanel(
                      editor: editor,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  _saveError ?? _statusText(editor),
                  key: const Key('selection-status'),
                  style: _saveError == null
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The last point the drag reached, for committing a move or stroke on release.
  /// Pan end carries no position, so the editor's own preview point is used.
  Offset _lastPoint(LevelEditor editor) => editor.lastDragPoint ?? Offset.zero;

  String _statusText(LevelEditor editor) {
    final selected = editor.selected;
    if (selected == null) return 'Tap an entity to select it.';
    final index = editor.document.entities.indexOf(selected);
    return 'Selected: ${selected.name ?? 'entity ${index + 1}'}';
  }

  /// Canvas extent in world units: at least the tile map, and always large
  /// enough to reach every entity, so a designer can place or drag one outside
  /// the map. A margin keeps markers at the edge reachable.
  Size _canvasSize(LevelEditor editor) {
    final geometry = editor.geometry;
    final map = geometry.tileMap;
    var width = map == null ? 320.0 : map.cols * map.tileWidth;
    var height = map == null ? 240.0 : map.rows * map.tileHeight;
    for (final at in geometry.entityPositions.values) {
      if (at.dx > width) width = at.dx;
      if (at.dy > height) height = at.dy;
    }
    return Size(width + 64, height + 64);
  }
}

/// The tool picker: one button per [EditorTool], with the active one selected.
class _Toolbar extends StatelessWidget {
  final EditorTool tool;
  final ValueChanged<EditorTool> onChanged;

  const _Toolbar({required this.tool, required this.onChanged});

  static const _labels = {
    EditorTool.select: ('Select', Icons.near_me_outlined),
    EditorTool.move: ('Move', Icons.open_with),
    EditorTool.paintTile: ('Paint', Icons.brush_outlined),
    EditorTool.eraseTile: ('Erase', Icons.auto_fix_off_outlined),
    EditorTool.fill: ('Fill', Icons.format_color_fill),
    EditorTool.placeEntity: ('Place', Icons.add_location_alt_outlined),
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: SegmentedButton<EditorTool>(
        key: const Key('tool-bar'),
        segments: [
          for (final entry in _labels.entries)
            ButtonSegment(
              value: entry.key,
              label: Text(entry.value.$1),
              icon: Icon(entry.value.$2),
            ),
        ],
        selected: {tool},
        onSelectionChanged: (set) => onChanged(set.first),
      ),
    );
  }
}
