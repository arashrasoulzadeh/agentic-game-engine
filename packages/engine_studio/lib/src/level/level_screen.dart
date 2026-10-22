import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart'
    show FileLock, LockInfo, lockOwner;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../inspector/inspector_panel.dart';
import '../assets/asset_index.dart';
import '../assets/brush_panel.dart';
import '../assets/project_stores.dart';
import '../palette/entity_palette.dart';
import '../validation/validation_panel.dart';
import '../playtest/play_test.dart';
import '../project/studio_project.dart';
import '../preview/preview_view.dart';
import 'editor_shortcuts.dart';
import 'level_canvas.dart';
import 'level_saver.dart';
import 'level_editor.dart';
import '../prefs/strings.dart';

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

  /// Starts the game process on the level (the "Run game" button). Null uses the real
  /// launcher; tests pass one with a recording process starter.
  final PlayTest? playTest;

  /// Who is editing, for the advisory file lock (see [FileLock]). Null uses `user@host`.
  final String? lockedAs;

  const LevelScreen({
    super.key,
    required this.levelPath,
    this.projectRoot,
    this.autosaveInterval = const Duration(seconds: 30),
    this.playTest,
    this.lockedAs,
  });

  @override
  State<LevelScreen> createState() => _LevelScreenState();
}

class _LevelScreenState extends State<LevelScreen> {
  LevelEditor? _editor;
  AssetIndex? _assets;
  String? _loadError;
  Timer? _autosave;
  bool _previewing = false;
  bool _running = false;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  String? _saveError;
  late final FileLock _lock = FileLock(widget.levelPath);
  late final String _me = widget.lockedAs ?? lockOwner();

  /// Set when someone else holds the level's lock: this editor is then view-only.
  LockInfo? _lockedBy;
  bool _holdsLock = false;

  @override
  void initState() {
    super.initState();
    try {
      final json =
          jsonDecode(File(widget.levelPath).readAsStringSync())
              as Map<String, dynamic>;
      final editor = LevelEditor(LevelDocument.fromJson(json));
      final root = widget.projectRoot;
      if (root != null) {
        // Project-level help for the editor: which sprites exist (so a missing one is
        // flagged) and how to load a prefab for a prefab brush.
        _assets = AssetIndex.scan(root);
        editor
          ..atlasRegions = _assets!.declaredRegions
          ..prefabLoader = PrefabStore(root).load;
      }
      _editor = editor;
    } on Object catch (e) {
      _loadError = 'Could not open ${widget.levelPath}: $e';
    }
    if (_editor != null && widget.projectRoot != null) {
      final result = _lock.acquire(_me);
      _holdsLock = result.acquired;
      _lockedBy = result.acquired ? null : result.holder;
    }
    final interval = widget.autosaveInterval;
    if (interval != null && widget.projectRoot != null) {
      _autosave = Timer.periodic(interval, (_) => _backUpIfDirty());
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _gameLauncher.stop();
    if (_holdsLock) _lock.release(_me);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  late final PlayTest _gameLauncher = widget.playTest ?? PlayTest();

  /// Asks Flutter which devices exist (not at startup: it can take seconds), then lets the designer pick
  /// the one the game runs on.
  Future<void> _chooseDevice() async {
    final devices = await _gameLauncher.listDevices();
    if (!mounted) return;
    final picked = await showDialog<PlayTestDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const Key('device-dialog'),
        title: Text(StudioStrings.t('level.device')),
        children: [
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No devices found.'),
            ),
          for (final d in devices)
            SimpleDialogOption(
              key: Key('device-${d.id}'),
              onPressed: () => Navigator.of(context).pop(d),
              child: Text('${d.name} (${d.id})'),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _gameLauncher.device = picked.id);
  }

  /// Starts the game on the level as it is now, edits included. Needs the level to
  /// belong to a project, since the snapshot is written into it.
  void _playTest() {
    if (_editor == null) {
      return;
    }
    setState(() {
      _previewing = true;
      _running = true;
    });
  }

  /// Runs the project's own game on the level as it is now, in a separate process (a
  /// crash there cannot take the studio down). Needs the level to belong to a project: the
  /// snapshot is written into it.
  Future<void> _runGame() async {
    final editor = _editor;
    final root = widget.projectRoot;
    if (editor == null || root == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final process = await _gameLauncher.launch(
        StudioProject.open(root),
        editor.document,
      );
      if (mounted) setState(() {});
      // The game can also end by itself (a crash, the player closing it): the button follows.
      process.exitCode.then((_) {
        if (mounted) setState(() {});
      });
      messenger.showSnackBar(
        SnackBar(
          key: const Key('run-game-started'),
          content: Text(StudioStrings.t('level.gameStarted')),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('run-game-failed'),
          content: Text('Could not start the game: $e'),
        ),
      );
    }
  }

  /// Takes the lock from whoever has it, for when their editor crashed or they walked away.
  void _takeOver() {
    _lock.release(_me, force: true);
    final result = _lock.acquire(_me);
    setState(() {
      _holdsLock = result.acquired;
      _lockedBy = result.acquired ? null : result.holder;
    });
  }

  /// Writes the level file. A failure stays on screen rather than being lost, and
  /// the level stays dirty so nothing is marked saved that was not.
  void _save() {
    final editor = _editor;
    if (editor == null || _lockedBy != null) return;
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
        appBar: AppBar(title: Text(StudioStrings.t('level.title'))),
        body: Center(child: Text(_loadError!, key: const Key('level-error'))),
      );
    }

    final title = widget.levelPath.split(Platform.pathSeparator).last;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
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
              key: const Key('playtest'),
              tooltip: StudioStrings.t('level.runPreview'),
              onPressed: _playTest,
              icon: const Icon(Icons.play_arrow),
            ),
            if (widget.projectRoot != null)
              IconButton(
                key: Key(_gameLauncher.isRunning ? 'stop-game' : 'run-game'),
                tooltip: StudioStrings.t(
                  _gameLauncher.isRunning ? 'level.stopGame' : 'level.runGame',
                ),
                onPressed: _gameLauncher.isRunning
                    ? () => setState(_gameLauncher.stop)
                    : _runGame,
                icon: Icon(
                  _gameLauncher.isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.rocket_launch_outlined,
                ),
              ),
            if (widget.projectRoot != null)
              IconButton(
                key: const Key('game-device'),
                tooltip:
                    '${StudioStrings.t('level.device')}: ${_gameLauncher.device}',
                icon: const Icon(Icons.devices_outlined),
                onPressed: _chooseDevice,
              ),
            IconButton(
              key: const Key('save'),
              tooltip: StudioStrings.t('level.save'),
              onPressed: editor.isDirty && _lockedBy == null ? _save : null,
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
            _ToggleIcon(
              keyName: 'toggle-grid',
              tooltip: StudioStrings.t('level.showGrid'),
              icon: Icons.grid_on,
              on: editor.gridVisible,
              onPressed: () => _edit((e) => e.gridVisible = !e.gridVisible),
            ),
            _ToggleIcon(
              keyName: 'toggle-snap',
              tooltip: StudioStrings.t('level.snapGrid'),
              icon: Icons.align_horizontal_left,
              on: editor.snapToGrid,
              onPressed: () => _edit((e) => e.snapToGrid = !e.snapToGrid),
            ),
            _ToggleIcon(
              keyName: 'toggle-tiles',
              tooltip: StudioStrings.t('level.showTiles'),
              icon: Icons.view_module_outlined,
              on: editor.showTiles,
              onPressed: () => _edit((e) => e.showTiles = !e.showTiles),
            ),
            _ToggleIcon(
              keyName: 'toggle-entities',
              tooltip: StudioStrings.t('level.showEntities'),
              icon: Icons.place_outlined,
              on: editor.showEntities,
              onPressed: () => _edit((e) => e.showEntities = !e.showEntities),
            ),
            IconButton(
              key: const Key('delete-selected'),
              tooltip: StudioStrings.t('level.deleteSelected'),
              onPressed: editor.selected == null
                  ? null
                  : () => _edit((e) => e.deleteSelected()),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_lockedBy != null)
              MaterialBanner(
                key: const Key('level-locked'),
                content: Text(
                  '${_lockedBy!.owner} is editing this level (since ${_lockedBy!.acquiredAt.toLocal().toString().substring(0, 16)}). '
                  'Saving is off so you do not overwrite their work.',
                ),
                actions: [
                  TextButton(
                    key: const Key('lock-take-over'),
                    onPressed: _takeOver,
                    child: Text(StudioStrings.t('level.takeOver')),
                  ),
                ],
              ),
            _ModeSwitch(
              previewing: _previewing,
              onChanged: (previewing) => setState(() {
                _previewing = previewing;
                _running = previewing;
              }),
            ),
            Expanded(
              child: _previewing
                  ? PreviewView(
                      document: editor.document,
                      running: _running,
                      projectRoot: widget.projectRoot,
                    )
                  : Column(
                      children: [
                        _Toolbar(
                          tool: editor.tool,
                          onChanged: (tool) => _edit((e) => e.tool = tool),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 200,
                                child: Column(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: EntityPalette(
                                        editor: editor,
                                        onChanged: () => setState(() {}),
                                      ),
                                    ),
                                    if (widget.projectRoot != null)
                                      Expanded(
                                        flex: 2,
                                        child: BrushPanel(
                                          editor: editor,
                                          projectRoot: widget.projectRoot!,
                                          onChanged: () => setState(() {}),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Scrollbar(
                                  controller: _vertical,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _vertical,
                                    child: Scrollbar(
                                      controller: _horizontal,
                                      thumbVisibility: true,
                                      notificationPredicate: (n) =>
                                          n.depth == 1,
                                      child: SingleChildScrollView(
                                        controller: _horizontal,
                                        scrollDirection: Axis.horizontal,
                                        child: Semantics(
                                          label:
                                              'Level canvas: tap or drag to use the selected tool',
                                          child: GestureDetector(
                                            key: const Key('level-canvas'),
                                            behavior: HitTestBehavior.opaque,
                                            onTapUp: (details) => _edit(
                                              (e) =>
                                                  e.tap(details.localPosition),
                                            ),
                                            onPanStart: (details) => _edit(
                                              (e) => e.dragStart(
                                                details.localPosition,
                                              ),
                                            ),
                                            onPanUpdate: (details) => _edit(
                                              (e) => e.dragUpdate(
                                                details.localPosition,
                                              ),
                                            ),
                                            onPanEnd: (_) => _edit(
                                              (e) => e.dragEnd(_lastPoint(e)),
                                            ),
                                            child: CustomPaint(
                                              size: _canvasSize(editor),
                                              painter: LevelCanvasPainter(
                                                editor: editor,
                                              ),
                                            ),
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
                                projectRoot: widget.projectRoot,
                                assets: _assets,
                              ),
                            ],
                          ),
                        ),
                        ValidationPanel(
                          editor: editor,
                          onSelect: () => setState(() {}),
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
                                : TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Runs an editor shortcut. Letter keys are ignored while a text field has
  /// focus, so typing a value in the inspector never switches tools.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final editor = _editor;
    if (editor == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_textFieldHasFocus()) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final shortcut = shortcutFor(
      event.logicalKey,
      command: keyboard.isMetaPressed || keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
    );
    if (shortcut == null) return KeyEventResult.ignored;

    switch (shortcut.action) {
      case EditorAction.undo:
        _edit((e) => e.undo());
      case EditorAction.redo:
        _edit((e) => e.redo());
      case EditorAction.save:
        _save();
      case EditorAction.deleteSelected:
        _edit((e) => e.deleteSelected());
      case EditorAction.toggleGrid:
        _edit((e) => e.gridVisible = !e.gridVisible);
      case EditorAction.tool:
        _edit((e) => e.tool = shortcut.tool!);
    }
    return KeyEventResult.handled;
  }

  bool _textFieldHasFocus() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

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

/// An app-bar button that shows whether a view setting is on.
class _ToggleIcon extends StatelessWidget {
  final String keyName;
  final String tooltip;
  final IconData icon;
  final bool on;
  final VoidCallback onPressed;

  const _ToggleIcon({
    required this.keyName,
    required this.tooltip,
    required this.icon,
    required this.on,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key(keyName),
      tooltip: tooltip,
      isSelected: on,
      onPressed: onPressed,
      icon: Icon(icon),
      selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
    );
  }
}

/// Switches the level screen between editing and the running preview.
class _ModeSwitch extends StatelessWidget {
  final bool previewing;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({required this.previewing, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SegmentedButton<bool>(
        key: const Key('mode-switch'),
        segments: [
          ButtonSegment(
            value: false,
            label: Text(StudioStrings.t('level.modeEdit')),
            icon: Icon(Icons.edit_outlined),
          ),
          ButtonSegment(
            value: true,
            label: Text(StudioStrings.t('level.modePreview')),
            icon: Icon(Icons.play_circle_outline),
          ),
        ],
        selected: {previewing},
        onSelectionChanged: (set) => onChanged(set.first),
      ),
    );
  }
}
