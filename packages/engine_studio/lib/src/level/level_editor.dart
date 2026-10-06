import 'dart:ui';

import 'package:engine_core/engine_core.dart';

import 'level_geometry.dart';

/// What a pointer gesture does on the canvas. Each tool turns input into
/// commands; none of them mutates the document directly.
enum EditorTool { select, move, paintTile, eraseTile, fill, placeEntity }

/// The editing session for one level: the document, its undo history, the
/// active tool, and the current selection. Pure Dart, so every tool's behavior
/// is testable without a widget tree.
///
/// Every change goes through [CommandHistory], which is what makes undo and redo
/// exact and what lets a paint drag undo as one step.
class LevelEditor {
  final LevelDocument document;
  final CommandHistory history;

  EditorTool tool = EditorTool.select;

  /// The tile id the paint tool writes. Id 0 is empty and is what erase writes.
  int paintTileId = 1;

  /// The entity under the last select, or null.
  LevelEntity? selected;

  /// An in-progress move: the entity being dragged and where it is now, shown
  /// as a preview until the drag ends and the move is committed.
  LevelEntity? _dragging;
  Offset? _dragPosition;

  /// The last point a drag reported, so release can commit at the right place
  /// even though the gesture's end event carries no position.
  Offset? lastDragPoint;

  /// Tile cells painted during the current drag, so the whole stroke undoes as
  /// one step.
  List<EditCommand>? _stroke;

  /// The level as last saved or loaded, encoded, so [isDirty] is a plain
  /// comparison. Undoing back to this state is therefore clean again.
  String _savedText;

  LevelEditor(this.document)
    : history = CommandHistory(document),
      _savedText = encodeLevelJson(document.toJson());

  /// Whether the level differs from its last saved state.
  bool get isDirty => encodeLevelJson(document.toJson()) != _savedText;

  /// Records the current state as saved. Call after a successful write.
  void markSaved() => _savedText = encodeLevelJson(document.toJson());

  /// Geometry for the document as it is right now. Recomputed on each read, so a
  /// view never shows positions from before the latest command.
  LevelGeometry get geometry => LevelGeometry.of(document);

  /// Where [entity] should be drawn: its preview position while it is being
  /// dragged, otherwise its stored position. Null when it has no readable position.
  Offset? displayPositionOf(LevelEntity entity) {
    if (identical(entity, _dragging) && _dragPosition != null) {
      return _dragPosition;
    }
    final index = document.entities.indexOf(entity);
    return index < 0 ? null : geometry.entityPositions[index];
  }

  bool get isDragging => _dragging != null || _stroke != null;

  // --- pointer gestures ---------------------------------------------------

  /// A tap at world point [point]. Select picks the entity under it, place adds a
  /// new entity there, and the tile tools act on the cell under it.
  void tap(Offset point) {
    switch (tool) {
      case EditorTool.select:
        selected = _entityAt(point);
      case EditorTool.move:
        selected = _entityAt(point) ?? selected;
      case EditorTool.placeEntity:
        _placeAt(point);
      case EditorTool.paintTile:
      case EditorTool.eraseTile:
        _paintCell(point, tool == EditorTool.paintTile ? paintTileId : 0);
      case EditorTool.fill:
        _fillAt(point);
    }
  }

  /// A drag begins at [point]. Only move and the tile-paint tools start one.
  void dragStart(Offset point) {
    lastDragPoint = point;
    switch (tool) {
      case EditorTool.move:
        final entity = _entityAt(point);
        if (entity == null) return;
        selected = entity;
        _dragging = entity;
        _dragPosition = displayPositionOf(entity);
      case EditorTool.paintTile:
      case EditorTool.eraseTile:
        _stroke = [];
        _paintCell(point, tool == EditorTool.paintTile ? paintTileId : 0);
      case EditorTool.select:
      case EditorTool.placeEntity:
      case EditorTool.fill:
        break;
    }
  }

  /// The drag moved to [point].
  void dragUpdate(Offset point) {
    lastDragPoint = point;
    if (_dragging != null) {
      _dragPosition = point;
    } else if (_stroke != null) {
      _paintCell(point, tool == EditorTool.paintTile ? paintTileId : 0);
    }
  }

  /// The drag ended at [point]. A move commits as one command; a paint stroke
  /// commits as one undo group.
  void dragEnd(Offset point) {
    final moved = _dragging;
    if (moved != null) {
      final at = point;
      _dragging = null;
      _dragPosition = null;
      history.execute(MoveEntityCommand(entity: moved, x: at.dx, y: at.dy));
    }
    final stroke = _stroke;
    if (stroke != null) {
      _stroke = null;
      if (stroke.isNotEmpty) {
        history.recordApplied(CompositeCommand('Paint stroke', stroke));
      }
    }
  }

  // --- tools --------------------------------------------------------------

  LevelEntity? _entityAt(Offset point) {
    final index = geometry.entityAt(point);
    return index == null ? null : document.entities[index];
  }

  void _placeAt(Offset point) {
    final entity = LevelEntity(
      components: {
        'position': {'x': point.dx, 'y': point.dy},
      },
    );
    history.execute(AddEntityCommand(entity));
    selected = entity;
  }

  /// Converts the level's tile map to flat ids the first time a tile tool is used,
  /// so tile edits can address cells. Undoable like any other edit.
  bool _ensureFlatTileMap() {
    final entity = _tileMapEntity();
    if (entity == null) return false;
    if (entity.components['tileMap']!.containsKey('legend')) {
      history.execute(FlattenTileMapCommand(entity));
    }
    return true;
  }

  LevelEntity? _tileMapEntity() {
    for (final entity in document.entities) {
      if (entity.components.containsKey('tileMap')) return entity;
    }
    return null;
  }

  /// The tile cell at world [point], as (col, row), or null when there is no tile
  /// map or the point is outside it.
  (int, int)? _cellAt(Offset point) {
    final map = geometry.tileMap;
    if (map == null) return null;
    final local = point - geometry.tileOrigin;
    final col = (local.dx / map.tileWidth).floor();
    final row = (local.dy / map.tileHeight).floor();
    if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return null;
    return (col, row);
  }

  void _paintCell(Offset point, int tileId) {
    final cell = _cellAt(point);
    if (cell == null || !_ensureFlatTileMap()) return;
    final command = SetTileCommand(
      entity: _tileMapEntity()!,
      col: cell.$1,
      row: cell.$2,
      tileId: tileId,
    );
    final stroke = _stroke;
    if (stroke != null) {
      command.apply(document);
      stroke.add(command);
    } else {
      history.execute(command);
    }
  }

  void _fillAt(Offset point) {
    final cell = _cellAt(point);
    if (cell == null || !_ensureFlatTileMap()) return;
    history.execute(
      FillRegionCommand(
        entity: _tileMapEntity()!,
        col: cell.$1,
        row: cell.$2,
        tileId: paintTileId,
      ),
    );
  }

  // --- history ------------------------------------------------------------

  /// Undoes the latest command. The selection is dropped if undo removed the
  /// selected entity, so it never points at something no longer in the level.
  void undo() {
    history.undo();
    _dropMissingSelection();
  }

  /// Re-applies the latest undone command, with the same selection rule as [undo].
  void redo() {
    history.redo();
    _dropMissingSelection();
  }

  void _dropMissingSelection() {
    final entity = selected;
    if (entity != null && !document.entities.contains(entity)) {
      selected = null;
    }
  }

  // --- deletion -----------------------------------------------------------

  /// Removes the selected entity as one undoable command. Does nothing when
  /// nothing is selected.
  void deleteSelected() {
    final entity = selected;
    if (entity == null) return;
    history.execute(RemoveEntityCommand(entity));
    selected = null;
  }
}
